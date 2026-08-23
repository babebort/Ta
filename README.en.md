<div align="center">

<img src="./Resources/Brand/Ta-AppIcon.png" width="128" alt="Ta Logo">

# Ta · 拓

### A thousand years ago, ink lifted words from stone. Today, AI lifts information from your screen.

[![License: MIT](https://img.shields.io/badge/License-MIT-D6402F.svg)](./LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/macOS-14%2B-1A1A1A.svg)](https://www.apple.com/macos/)
[![Swift: 6.2](https://img.shields.io/badge/Swift-6.2-F05138.svg)](https://www.swift.org/)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha-C98B2E.svg)](#project-status)

**An AI-native screenshot tool for macOS: capture, OCR, translate, stitch, pin, and annotate in one flow.**

[简体中文](./README.md) · [English](./README.en.md) · [日本語](./README.ja.md)

</div>

![Ta home screen](./docs/brand/Ta-home-preview.png)

## More than a thousand years ago, China had its own kind of “screenshot”

Before cameras, photocopiers, or modern printing, people faced a practical question: how could they take the writing on a stone stele home?

They laid paper over the stone and gently dabbed it with ink. When the paper was lifted, the characters left the stone and travelled with them. This craft is called **ink rubbing**—*tà yìn* (拓印)—and it has been practised for more than a thousand years. It was an ancient way to capture what you saw and keep it.

The character 「拓」 tells the same story: `hand + stone`. The Chinese name is pronounced `tà`; the English name is **Ta**.

Today, the stone has become a screen. Information appears faster and disappears faster. Ta does the same job: frame it and lift it out. Text becomes copyable and translatable; images can be annotated or pinned in view. A scrolling capture lifts the whole “stele,” while AI acts like a pocket epigrapher, helping you read what you captured.

> Cangjie created characters; ink rubbing carried them forward. Creating information is only the beginning—it is complete when it can be preserved, understood, and taken with you.

## Why I built Ta

I use screenshot software almost every day. There are countless free and paid options, but after trying many of them, I still could not find one tool that covered everything I needed. OCR, translation, scrolling capture, image pins, annotation, and publishing-ready styling were scattered across different apps and disconnected workflows.

So I decided to build one.

Most screenshot apps add OCR or an isolated AI button to an existing workflow. Ta is an attempt to make AI part of the workflow itself—and to keep improving that experience around real, everyday needs, first mine and then yours.

## What “AI-native screenshot tool” means

AI-native does not mean attaching a chat box to a traditional screenshot app. It means AI can help from the moment a capture is made:

- **Capture it** — grab a region, a window, or a scrolling page;
- **Read it** — extract text, tables, formulas, and code with local OCR or multimodal models;
- **Understand it** — translate, explain, and structure what is on the screen;
- **Keep it useful** — copy, pin, annotate, beautify, save, or continue processing;
- **Respect boundaries** — prefer local recognition, ask before cloud processing, and keep API keys in macOS Keychain.

## Problems it solves

- **Too much work after capture** — OCR, translation, copy, save, and annotation live in one flow.
- **Unreliable scrolling screenshots** — manual or automatic scrolling, duplicate-frame filtering, fixed-region removal, seam review, and manual correction.
- **One OCR engine does not fit every task** — switch among Apple Vision, PaddleOCR, and remote vision services based on speed, structure, and privacy.
- **Slow annotation workflows** — in-place annotation, direct object manipulation, brush mosaic, and floating image pins inspired by Snipaste.
- **Unclear cloud boundaries** — local processing by default, explicit upload notices, and API keys stored in macOS Keychain.

## How it works

Ta uses a native macOS capture pipeline:

```text
Global shortcut
    ↓
Select a screen region
    ↓
ScreenCaptureKit capture (excluding Ta's own windows)
    ↓
┌────────────────┬────────────────────┐
│ Local OCR      │ Multimodal vision  │
│ Apple Vision   │ OpenAI-compatible  │
│ PaddleOCR      │ Claude / Gemini    │
└────────────────┴────────────────────┘
    ↓
Copy · Translate · Pin · Annotate · Stitch · Save
```

If the clipboard changes while recognition is running, Ta will not overwrite the user's newer clipboard content. When no text is found, the workflow can safely fall back to copying a PNG.

## Core features

### Capture and shortcuts

- A universal capture toolbar with OCR, AI vision, translation, copy, pin, annotate, beautify, and save actions.
- Dedicated global shortcuts for instant OCR, image copy, translation, pinning, and scrolling capture.
- Record custom shortcuts, detect conflicts, and restore defaults from Settings.
- Cancel region selection with right-click or `Escape` without creating a file or changing the clipboard.
- Hide Ta while capturing so the app neither steals focus nor appears inside the capture.

### OCR and AI vision

- **Apple Vision** — the default local OCR path for Chinese, English, and common text layouts.
- **PaddleOCR optional pack** — offline on Apple Silicon, with install, update, checksum, warm-up, and persistent worker support.
- **DeepSeek-OCR-2** — connect to a user-hosted vLLM, SGLang, or compatible vision endpoint; Ta does not silently download large model weights.
- **Multimodal providers** — OpenAI-compatible, Azure OpenAI, Anthropic Claude, and Google Gemini protocols.
- Task templates for exact text extraction, code explanation, Markdown/CSV tables, LaTeX formulas, and general visual understanding.
- OCR-only, model-only, or local-first smart routing with explicit confirmation before upload.

### Screenshot translation

- Customizable source and target languages; the default is auto-detect to Simplified Chinese.
- Translate a capture and copy the result directly to the clipboard.
- Return plain text, replace text inside the image, or append a bilingual panel below the original.
- Text localization and final image composition happen locally; only text that needs translation is sent to the configured model.

### Scrolling capture

- Manual or automatic scrolling capture for browsers, chats, and common desktop apps.
- Match adjacent frames, filter duplicates, and detect scroll direction.
- Detect and remove fixed headers, footers, and input areas.
- Review seams before export and adjust them by `±1` or `±10 px`.
- Segment extremely tall images to reduce memory and export pressure.

### Annotation and image pins

- Annotate in place over a translucent overlay while the capture stays where it was taken.
- Rectangle, ellipse, arrow, pen, highlighter, text, numbering, mosaic, blur, eraser, and magnifier tools.
- Select, move, resize, rotate, and re-edit annotation objects directly.
- Mosaic supports both rectangular selection and freehand painting.
- Pins support drag, resize, opacity, rotation, flip, filters, crop, click-through, groups, hide/restore, and double-click to close.
- Create pins from captures, clipboard images, text, HTML, or files.

## Quick start

### Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac (the packaged PaddleOCR add-on currently targets Apple Silicon)
- Xcode 26 or another Swift 6.2-compatible toolchain

### Build from source

```bash
git clone https://github.com/kangarooking/Ta.git
cd Ta
swift test
./scripts/build-app.sh
open "artifacts/拓.app"
```

On first launch, grant Screen & System Audio Recording permission. Accessibility permission is only required for automatic scrolling capture.

### Default shortcuts

| Action | Shortcut |
|--------|----------|
| Instant OCR | `⇧⌥⌘1` |
| Universal capture | `⇧⌥⌘2` |
| Copy image | `⇧⌥⌘3` |
| Capture and pin | `⇧⌥⌘4` |
| Scrolling capture | `⇧⌥⌘5` |
| Screenshot translation | `⇧⌥⌘6` |

Open **Settings → Shortcuts** to record any new combination. Conflicting shortcuts are rejected or rolled back automatically.

## Privacy and security

- Standard capture and Apple Vision OCR always run on-device.
- The PaddleOCR add-on runs offline after installation.
- A selected region or extracted text is sent out only when the user explicitly chooses remote OCR, multimodal vision, or translation.
- Low-confidence smart routing never uploads silently and always requires confirmation.
- API keys are stored only in macOS Keychain, never in preferences, logs, or this repository.
- Ta does not continuously record the screen; it reads only a region the user actively selects.

## Repository structure

```text
Ta/
├── README.md / README.en.md / README.ja.md
├── Package.swift
├── Resources/                 icons, Info.plist, and brand assets
├── Sources/
│   ├── AIScreenshotCore/      OCR, stitching, providers, clipboard policy
│   └── AIScreenshotApp/       capture, editor, routing, system, and UI
├── Tests/                     Core and App tests
├── ocr-packs/paddleocr/       optional PaddleOCR pack definitions
├── scripts/                   build, run, and OCR pack scripts
└── docs/                      PRD, research, validation, and plans
```

## Project status

Ta is currently **Alpha** software. Its core workflows are functional, but it is not yet a notarized public release.

Known limitations:

- Region selection currently focuses on the display under the pointer; cross-display selection and automatic window snapping are not complete.
- Scrolling capture can still require manual seam correction on video, animation, translucent overlays, or heavily reflowing layouts.
- Image translation uses local cover-and-redraw composition; complex textures, gradients, shadows, vertical text, and dense layouts can leave artifacts.
- The repository contains PaddleOCR pack definitions, not the large locally built archives or model weights.
- Local builds prefer Apple Development signing; public distribution still requires Developer ID signing and Apple notarization.

## Documentation

- [Product requirements (Chinese)](./AI截图软件-产品需求文档-PRD-v1.0.md)
- [Market and user pain-point research (Chinese)](./AI截图软件市场与用户痛点调研.md)
- [Alpha verification](./docs/alpha-verification.md)
- [Scrolling capture acceptance matrix](./docs/long-capture-acceptance-matrix.md)
- [PaddleOCR add-on specification](./docs/ocr-enhancement-pack-spec.md)

## Roadmap

- [x] Native capture, OCR, clipboard output, and custom shortcuts
- [x] Scrolling capture, automatic scrolling, and seam review
- [x] In-place annotation, brush mosaic, and image pins
- [x] Screenshot translation and multi-provider configuration
- [x] Optional offline PaddleOCR pack protocol
- [ ] Cross-display region selection and window snapping
- [ ] Publishing templates and parameterized screenshot styling
- [ ] History, search, and result re-copy
- [ ] Developer ID signing, notarization, and public installer

## Free, open source, and built together

Ta is free and open source under the [MIT License](./LICENSE). Anyone can download the source, build it, use it, modify it, and redistribute it.

The project is still in Alpha. If your screenshot workflow has a problem Ta does not solve yet, open an Issue. If you would like to help improve it, pull requests are welcome. Read [CONTRIBUTING.md](./CONTRIBUTING.md) before making changes, and include tests or reproducible validation steps for behavioral changes.

If Ta saves you an app switch or a repetitive step, please give the project a **Star**. It is the simplest way to support its development.

## Author

**Kangarooking (袋鼠帝)** — AI creator and independent developer behind the Chinese publication “袋鼠帝 AI 客栈”.

| Platform | Link |
|----------|------|
| GitHub | [@kangarooking](https://github.com/kangarooking) |
| X / Twitter | [@aikangarooking](https://x.com/aikangarooking) |
| Cangjie Skill | [kangarooking/cangjie-skill](https://github.com/kangarooking/cangjie-skill) |

## ⭐ Star History

If Ta helps you, consider giving the project a Star.

<a href="https://www.star-history.com/?repos=kangarooking%2FTa&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=kangarooking/Ta&type=date&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=kangarooking/Ta&type=date&legend=top-left" />
   <img alt="Ta Star History Chart" src="https://api.star-history.com/chart?repos=kangarooking/Ta&type=date&legend=top-left" />
 </picture>
</a>

## License

MIT. See [LICENSE](./LICENSE).
