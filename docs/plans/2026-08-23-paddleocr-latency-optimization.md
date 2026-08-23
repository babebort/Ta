# PaddleOCR Latency Optimization Implementation Plan

**Goal:** Keep ordinary local PaddleOCR recognition below five seconds after warm-up, with a target of one to two seconds for common screenshots.

**Architecture:** Extend the optional OCR pack with a JSON Lines worker mode that loads PaddleOCR once and handles multiple requests. The macOS host owns one serialized worker, warms it when PaddleOCR is selected, scales only oversized images, and releases the process after five idle minutes. Packs without worker metadata continue using the existing one-shot process contract.

**Tech Stack:** Swift 6.2, AppKit/CoreGraphics, Foundation `Process`, Python 3.12, PaddleOCR 3.x, ONNX Runtime CPU.

---

### Task 1: Version and document the worker protocol

**Files:**
- Modify: `ocr-packs/paddleocr/adapter.py`
- Modify: `ocr-packs/paddleocr/manifest-template.json`
- Modify: `docs/ocr-enhancement-pack-spec.md`

1. Add `--worker`, a ready event, request IDs, ping/shutdown commands, and one JSON response per input line.
2. Keep `--input` and `--health-check` unchanged for backward compatibility.
3. Add per-request timing metrics and safe detection/batching limits.

### Task 2: Add the persistent macOS worker

**Files:**
- Create: `Sources/AIScreenshotApp/Recognition/PersistentOCRWorker.swift`
- Modify: `Sources/AIScreenshotApp/Recognition/OptionalOCRPackManager.swift`

1. Start the worker on a private serial queue and wait for its ready event.
2. Queue recognition requests, enforce startup/request timeouts, and restart once after a broken pipe or malformed response.
3. Downscale images only when their longest side exceeds 2560 pixels.
4. Stop the worker after five idle minutes and when its pack is removed or replaced.
5. Use one-shot execution for older manifests without worker metadata.

### Task 3: Warm the selected engine and expose status

**Files:**
- Modify: `Sources/AIScreenshotApp/App/AppModel.swift`
- Modify: `Sources/AIScreenshotApp/UI/SettingsView.swift`

1. Warm an installed PaddleOCR worker shortly after app launch when it is the selected OCR engine.
2. Warm after selecting, importing, installing, or updating PaddleOCR.
3. Explain the temporary memory tradeoff and idle release in Settings.

### Task 4: Test, package, and benchmark

**Files:**
- Modify: `Tests/AIScreenshotAppTests/OptionalOCRPackManagerTests.swift`
- Modify: `scripts/test-paddleocr-pack.sh`
- Modify: `scripts/build-paddleocr-pack.sh`
- Modify: `ocr-packs/paddleocr/catalog-template.json`

1. Test worker reuse, ordered requests, downscaling, old-pack fallback, and process restart.
2. Build PaddleOCR pack 1.1.0 and update its local catalog/checksums.
3. Run all Swift tests and the pack protocol test.
4. Benchmark cold start and at least two warm recognitions on a real Chinese screenshot.

## Acceptance criteria

- The first worker startup happens in the background when possible.
- Repeated common screenshots reuse one model process and complete within five seconds on the target Apple Silicon Mac.
- Only one recognition runs at a time; concurrent requests cannot interleave JSON responses.
- Images larger than 2560 pixels on either axis are scaled proportionally before OCR.
- The worker exits after five idle minutes, releasing its roughly 700–800 MB peak memory.
- A worker crash automatically retries once; an older 1.0.0 pack still works through the one-shot path.
