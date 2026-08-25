# Editing, pinning, and long capture

These capabilities belong to Ta's `Capture → Understand → Transform → Deliver` model, but command availability must come from the running app:

```bash
ta capabilities --json
```

The current Bridge v1 CLI exposes capture, OCR, analysis, translation, copy, and save. It does not yet expose beautification, JSON annotation recipes, redaction, pinning, or scrolling capture. Do not fabricate `ta transform`, `ta pin`, or `ta long-capture` commands, and do not claim a GUI-only capability was completed through the CLI.

When a future capability appears in `system.capabilities`, prefer reproducible, non-interactive recipes:

- Beautify: named preset plus explicit canvas, padding, background, shadow, and output format.
- Annotate: source artifact plus JSON objects with stable IDs and coordinates.
- Redact: explicit regions or reviewed detections; irreversible output must be a new artifact.
- Pin: visible action; warn that a window will appear even if it does not take focus.
- Long capture: default to a silent browser-native path. Native-app scrolling may change visible content and must pause on user activity.

Until those methods are exposed, report the capability gap and offer the existing Ta GUI only when the user is present and asks for an interactive workflow.
