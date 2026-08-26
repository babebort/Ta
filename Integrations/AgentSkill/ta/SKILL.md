---
name: ta
description: Use the Ta macOS app and ta CLI to capture displays, foreground apps, windows, or known regions without taking focus, then annotate, OCR, understand, translate, copy, or save images. Use when an Agent needs visual input or deterministic screenshot markup; do not use it as a general mouse-and-keyboard automation tool.
---

# Ta Screen Intelligence

Use Ta as the visual input layer. Ta owns macOS Screen Recording permission, model profiles, and secrets; the CLI only sends requests to its local bridge.

## Start safely

1. Run `scripts/check-ta.sh` once before the first Ta action in a task.
2. Read the JSON response. Continue only when top-level `ok` is `true` and `data.bridge` is `ready`.
3. Use `--json` for every command an Agent must inspect. Treat a request as successful only when top-level `ok` is `true`; image-producing commands must also return a non-empty `artifacts` array.
4. Do not request, read, print, or pass API keys. Model configuration stays in Ta.

If the check fails, follow [references/error-codes.md](references/error-codes.md). Do not repeatedly launch Ta or retry non-retryable errors.

## Choose the workflow

- Capture the current page or app: `ta capture frontmost --json`. Ta freezes the foreground target and should not activate itself, move the pointer, or send input events.
- Capture a particular visible window: list candidates first, then capture the returned ID. Read [references/capture-targeting.md](references/capture-targeting.md).
- Extract text: capture, then run local OCR. Read [references/image-understanding.md](references/image-understanding.md).
- Understand semantics, code, tables, or formulas: use `ta analyze` only when OCR is insufficient. This may use the configured cloud model.
- Translate visible content: choose text translation for a textual result or image translation for a rendered translated image. Read [references/image-understanding.md](references/image-understanding.md).
- Copy or save a result: do so only when the request calls for changing the clipboard or filesystem. Read [references/commands.md](references/commands.md).
- Annotate an image reproducibly: use `ta transform ... --recipe <JSON>` and keep stable IDs for later erasing. The transform is local and returns a new PNG Artifact. Read [references/editing-recipes.md](references/editing-recipes.md).
- Beautify, redact, pin, or long-capture: check `ta capabilities --json` first. Do not invent methods absent from the returned list.

## Privacy boundary

Ordinary screenshot requests are pre-authorized after the user grants Ta macOS permission. Still stop before capturing a password manager, banking/payment app, private-key or recovery-code screen, private browsing window, or another obviously sensitive target unless the user explicitly identifies that target for capture.

Use local OCR when text alone is enough. Do not silently switch a cloud-denied task to cloud processing or an unavailable silent long capture to an interactive flow. Read [references/privacy-and-safety.md](references/privacy-and-safety.md) for cloud, clipboard, and artifact rules.

## Report observable results

Report the target actually returned by Ta, whether cloud upload occurred, and the resulting text or artifact path. Temporary artifacts expire; save a durable copy when the user needs the image later. Never claim success from command dispatch alone.
