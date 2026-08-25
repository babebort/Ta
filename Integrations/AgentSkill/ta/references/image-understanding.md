# Image understanding and translation

## Prefer the least invasive route

1. Text only: use `ta ocr`. This uses the OCR engine configured in Ta and can remain local.
2. Semantic interpretation or structure: use `ta analyze` with the narrowest matching task.
3. Translation: OCR plus text translation for copyable text; image translation only when layout-preserving visual output is requested.

Do not send the image to a cloud model merely to recover ordinary readable text. If cloud use is forbidden, pass `--cloud deny`; do not retry with `allow` after `CLOUD_UPLOAD_NOT_ALLOWED`.

## Reliable chaining

Capture and immediately consume the returned artifact, or use `last` only within the same clear workflow. In concurrent work, prefer the explicit artifact path so another request cannot replace “last”.

Examples:

```bash
ta capture frontmost --json
ta ocr last --languages zh-Hans,en-US --json
```

```bash
ta analyze /absolute/path/capture.png --task tableMarkdown --cloud auto --json
```

```bash
ta translate /absolute/path/capture.png --mode text --cloud auto --json
```

## Validate output

- OCR: require `ok: true`; report text, engine, languages, content type, and confidence when present.
- Analyze/translate text: require non-empty `data.text`; disclose `meta.cloudUploaded`.
- Image translation: require a non-empty artifact and verify its MIME type and dimensions.
- An empty OCR result is not a successful extraction. Consider a configured enhanced OCR engine or semantic analysis only if the user's privacy constraints allow it.
