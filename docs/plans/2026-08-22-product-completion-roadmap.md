# AI Screenshot Product Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the current macOS Alpha into a dependable Snipaste-class capture tool with universal scrolling screenshots, local/AI recognition, creator-focused annotation, and export.

**Architecture:** Keep capture, image processing, editing, recognition, pinning, and export as independent stages. Universal long capture repeatedly samples one user-selected screen region and estimates vertical movement from image content, so it works in browsers, WeChat, Codex, WorkBuddy, and other apps without relying on DOM access; Accessibility-driven auto-scroll is an optional accelerator, not a dependency.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, ScreenCaptureKit, Vision, Accelerate/CoreGraphics where useful, Carbon, Keychain, URLSession.

---

## Product and engineering decisions

### ADR-009: Universal long capture is image-based

- The user selects a stable viewport, then scrolls the target app normally.
- The app captures that same region at a short interval and finds the vertical shift between consecutive frames.
- Duplicate frames are ignored; valid new bottom strips are appended; low-confidence frames are skipped and reported.
- The first release supports downward scrolling. Reverse scrolling, horizontal canvases, and mixed-direction recovery are later extensions.
- Browser DOM capture may be added as a high-fidelity provider, but the baseline must work for native and Electron chat apps.

### ADR-010: Long-capture privacy and failure behavior

- Frames remain in memory until the user finishes or cancels.
- Finishing opens a save panel; cancelling discards every frame.
- No long-capture pixels are uploaded unless the user separately invokes an explicit AI action.
- The control HUD is excluded from ScreenCaptureKit through the existing own-process filter.
- If matching confidence is too low, keep the last trusted frame, skip the bad frame, and show a skipped-frame count rather than generating a corrupt image silently.

### ADR-011: Editing is non-destructive

- Annotation operations are stored as editable objects over the source image.
- Copy/export renders a flattened result; undo/redo changes the operation list.
- Creator beautification consumes the flattened or source image as a new document and never mutates the original capture.

## Acceptance matrix

| Stage | User-visible result | Verification |
|---|---|---|
| Save/export | “保存” writes PNG/JPEG without opening a fake placeholder | Save a capture and reopen the file |
| Annotation | Rectangle, ellipse, arrow, pen, text, mosaic, blur, undo/redo, copy/save | Render each tool and compare output dimensions |
| Window capture | Hover highlights window; keyboard can choose region/window/display | Test native, Electron, browser windows |
| Advanced pin | Zoom, opacity, rotate, mirror, crop, click-through, all Spaces | Exercise context menu and relaunch |
| Long capture MVP | User-selected region stitches downward scroll across arbitrary apps | Browser, WeChat, Codex, WorkBuddy test matrix |
| Multimodal | OpenAI-compatible vision request returns text/structure with explicit upload | Mock server plus one configured provider |
| AI creator tools | Auto emphasis, privacy redaction, canvas/background, multi-size export | WeChat article image preset test |

## Task 1: PNG/JPEG export foundation

**Files:**
- Create: `Sources/AIScreenshotApp/System/ImageExportService.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`

1. Add an AppKit save-panel service with PNG as the safe default and JPEG by extension.
2. Add deterministic image encoders and localized errors.
3. Route the existing Save quick action to the service.
4. Build and manually reopen an exported image.

## Task 2: Universal scrolling stitch engine

**Files:**
- Create: `Sources/AIScreenshotCore/LongCapture/VerticalScrollMatcher.swift`
- Create: `Sources/AIScreenshotApp/Capture/ScrollingImageStitcher.swift`
- Test: `Tests/AIScreenshotCoreTests/VerticalScrollMatcherTests.swift`

1. Write failing synthetic-frame tests for duplicates, downward shifts, and unrelated frames.
2. Implement a grayscale-row matcher that ignores sticky top/bottom margins.
3. Convert CGImages into compact grayscale samples.
4. Append only the new bottom strip to a CoreGraphics canvas.
5. Verify exact output height for synthetic captures.

## Task 3: Long-capture session and UI

**Files:**
- Create: `Sources/AIScreenshotApp/Capture/ScrollingCaptureSessionController.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`
- Modify: `Sources/AIScreenshotApp/App/AppModel.swift`
- Modify: `Sources/AIScreenshotApp/System/GlobalHotKeyManager.swift`
- Modify: `Sources/AIScreenshotApp/UI/MenuBarContentView.swift`
- Modify: `Sources/AIScreenshotApp/UI/WelcomeView.swift`

1. Select a region without the normal post-capture toolbar.
2. Start in-memory sampling and show a compact control HUD.
3. Allow Finish and Cancel; show accepted/skipped frame counts.
4. On Finish, stitch, copy the result, then offer PNG save.
5. Register `⇧⌥⌘5` and expose the command in the main/menu UI.
6. Validate in a long browser page and at least one native/Electron chat view.

## Task 4: Annotation editor and creator presets

**Files:**
- Create: `Sources/AIScreenshotApp/Editor/AnnotationDocument.swift`
- Create: `Sources/AIScreenshotApp/Editor/AnnotationCanvasView.swift`
- Create: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`

1. Add rectangle, ellipse, arrow, pen, marker, text, mosaic, and blur objects.
2. Add selection, move, resize, color, width, opacity, undo, and redo.
3. Add copy, PNG/JPEG save, and quick-save.
4. Add WeChat creator canvases: clean card, device frame, gradient background, shadow, margin, title/caption.
5. Verify exported pixels rather than only checking visible UI state.

## Task 5: Window/element capture and advanced pinning

**Files:**
- Create: `Sources/AIScreenshotApp/Capture/WindowTargetResolver.swift`
- Modify: `Sources/AIScreenshotApp/Capture/SelectionOverlayView.swift`
- Modify: `Sources/AIScreenshotApp/Capture/ScreenCaptureService.swift`
- Modify: `Sources/AIScreenshotApp/UI/PinnedImageWindowController.swift`

1. Resolve visible ScreenCaptureKit windows under the cursor and highlight them.
2. Add region/window/display modes, delayed capture, repeat region, cursor option, fixed ratio, and keyboard pixel adjustment.
3. Add pin rotate, mirror, crop, opacity display, click-through, topmost toggle, recover last closed, and hide/show all.
4. Verify mixed-scale multi-display coordinate conversion.

## Task 6: Real multimodal recognition

**Files:**
- Create: `Sources/AIScreenshotApp/Recognition/MultimodalRecognitionService.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`
- Modify: `Sources/AIScreenshotApp/UI/ModelSettingsView.swift`
- Test: add URLProtocol-backed request/response tests.

1. Validate the configured HTTPS/OpenAI-compatible endpoint.
2. Encode the selected image with bounded dimensions and quality.
3. Send an explicit vision request with timeout, cancellation, and useful error mapping.
4. Add prompts for plain text, table, code, formula, UI explanation, and translation.
5. Make smart routing local-first and require explicit confirmation before any cloud fallback.

## Task 7: AI creator features, history, and release QA

1. Add AI-suggested emphasis, sensitive-data redaction, layout cleanup, and alt-text generation.
2. Add local searchable capture history with retention controls and a private-mode toggle.
3. Add configurable shortcuts with conflict detection.
4. Run unit tests, stable-signed release build, permission relaunch test, and the app compatibility matrix.
5. Update README and PRD checklists only for behavior verified in the built `.app`.
