#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
PACK_DIR="${1:-$PROJECT_ROOT_DIR/.build/paddleocr-pack-portable/PaddleOCR-Pack-arm64-1.1.0}"
ADAPTER="$PACK_DIR/bin/paddleocr-adapter"
TEST_IMAGE="${2:-$PROJECT_ROOT_DIR/.build/paddleocr-demo.png}"

if [[ ! -x "$ADAPTER" ]]; then
    echo "Adapter is not executable: $ADAPTER" >&2
    exit 1
fi
if [[ ! -f "$TEST_IMAGE" ]]; then
    echo "Test image is missing: $TEST_IMAGE" >&2
    exit 1
fi

HEALTH_JSON="$($ADAPTER --health-check)"
OCR_JSON="$($ADAPTER --input "$TEST_IMAGE" --output json)"
WORKER_JSONL="$(
    printf '%s\n' \
        '{"id":"ping-1","command":"ping"}' \
        "{\"id\":\"ocr-1\",\"command\":\"recognize\",\"input\":\"$TEST_IMAGE\",\"detectionSideLimit\":2560}" \
        "{\"id\":\"ocr-2\",\"command\":\"recognize\",\"input\":\"$TEST_IMAGE\",\"detectionSideLimit\":2560}" \
        '{"id":"stop-1","command":"shutdown"}' \
    | "$ADAPTER" --worker
)"

python3 - "$HEALTH_JSON" "$OCR_JSON" "$WORKER_JSONL" <<'PY'
import json
import sys

health = json.loads(sys.argv[1])
result = json.loads(sys.argv[2])
worker = [json.loads(line) for line in sys.argv[3].splitlines() if line.strip()]
assert health["ok"] is True
assert health["architecture"] == "arm64"
assert health["offline"] is True
assert result["engine"] == "paddleOCR"
assert result["text"].strip()
assert 0 <= result["confidence"] <= 1
assert worker[0]["event"] == "ready"
assert worker[1] == {"id": "ping-1", "ok": True, "event": "pong"}
assert worker[2]["id"] == "ocr-1" and worker[2]["ok"] is True
assert worker[3]["id"] == "ocr-2" and worker[3]["ok"] is True
assert worker[2]["text"].strip() and worker[3]["text"].strip()
assert worker[2]["metrics"]["modelLoadMilliseconds"] == 0
assert worker[3]["metrics"]["modelLoadMilliseconds"] == 0
assert worker[4] == {"id": "stop-1", "ok": True, "event": "stopping"}
print(json.dumps({
    "health": health,
    "textPreview": result["text"][:160],
    "confidence": result["confidence"],
    "workerStartupMilliseconds": worker[0]["startupMilliseconds"],
    "warmInferenceMilliseconds": [
        worker[2]["metrics"]["inferenceMilliseconds"],
        worker[3]["metrics"]["inferenceMilliseconds"],
    ],
}, ensure_ascii=False, indent=2))
PY
