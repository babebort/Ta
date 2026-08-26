# CLI commands

Use `--json` in Agent workflows. Global options may appear anywhere:

```text
--json
--timeout <seconds>
--request-id <id>
--socket <path>
--cloud auto|allow|deny
```

## Inspect

```bash
ta status --json
ta capabilities --json
ta permissions --json
ta screen list --json
ta window list --json
ta window list --app "Safari" --json
```

`--app` accepts a visible app-name fragment or an exact Bundle ID. Use returned display and window IDs; do not guess them.

## Capture

```bash
ta capture frontmost --json
ta capture screen --json
ta capture screen --display 1 --json
ta capture window --window-id 1284 --json
ta capture region --display 1 --x 100 --y 120 --width 800 --height 600 --json
ta capture frontmost --output /absolute/path/capture.png --json
```

Region coordinates are global macOS screen coordinates. `--output` saves a durable copy while the response still describes the managed source artifact.

## Understand and translate

Commands without an image path use Ta's latest artifact:

```bash
ta ocr last --languages zh-Hans,en-US --json
ta ocr /absolute/path/image.png --json
ta analyze last --task general --cloud auto --json
ta analyze last --task extractText --cloud auto --json
ta analyze last --task explainCode --cloud auto --json
ta analyze last --task tableMarkdown --cloud auto --json
ta analyze last --task formulaLaTeX --cloud auto --json
ta translate last --mode text --cloud auto --json
ta translate last --mode image --cloud auto --json
ta translate text --text "Hello" --cloud auto --json
```

For `translate --mode text`, the CLI runs OCR and then text translation. Image mode returns a translated image artifact when the configured provider supports it.

## Deliver

```bash
ta copy last --json
ta copy --text "content" --json
ta save last --output /absolute/path/result.png --json
```

Copy mutates the user's clipboard. Save requires an explicit absolute destination. Never overwrite an existing user file unless the user requested that exact path.

## Annotate and transform

```bash
ta transform last --recipe /absolute/path/annotations.json --output /absolute/path/marked.png --json
ta transform /absolute/path/input.png --recipe /absolute/path/annotations.json --json
ta transform undo --output /absolute/path/previous.png --json
ta transform redo --output /absolute/path/restored.png --json
```

The CLI reads the local UTF-8 recipe and sends its contents—not the recipe path—to the Bridge. `last` uses the current Bridge image and edit session. An explicit input path starts a new edit session. Every successful command returns a new temporary PNG Artifact; `--output` additionally saves a durable copy.

Annotation transforms are local-only. Confirm `meta.cloudUploaded` is `false`, `artifacts` is non-empty, and `data.canUndo` / `data.canRedo` match the expected history state. See [editing-recipes.md](editing-recipes.md) for the versioned schema.

## Response contract

Success requires top-level `ok: true`. Image-producing success also requires at least one artifact with `path`, `mimeType`, `bytes`, `sha256`, and expiry metadata. `meta.cloudUploaded` is the authoritative disclosure for cloud usage. A successful transform also returns `width`, `height`, `elementCount`, `canUndo`, and `canRedo`.

Exit codes: `0` success, `2` usage, `3` app missing, `4` bridge unavailable, `5` permission denied, `6` privacy/cloud blocked, `7` request failure, `130` cancelled.
