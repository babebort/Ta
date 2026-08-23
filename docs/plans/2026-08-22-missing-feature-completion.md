# AI Screenshot Missing Feature Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the missing long-capture, annotation, pinning, multimodal-routing, and OCR capabilities requested for the macOS-first product.

**Architecture:** Preserve the existing stage separation: capture produces immutable pixels; long-capture and OCR engines operate in `AIScreenshotCore`; editing, review, pinning, permission prompts, and provider configuration live in `AIScreenshotApp`. Every external upload remains explicit, while optional heavyweight OCR engines are downloadable adapters rather than mandatory app payload.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, ScreenCaptureKit, Vision/VisionKit, CoreImage, CoreGraphics, Accessibility APIs, Carbon, Keychain, URLSession.

---

## Confirmed product decisions

1. Long capture must remain usable without Accessibility permission. Manual scrolling is the baseline; auto-scroll is opt-in and requests Accessibility only when invoked.
2. Sticky headers and footers are detected as same-position regions and removed from intermediate segments. The first header and final footer remain once.
3. A low-confidence seam is visible in review and can be excluded or adjusted before export. The app never silently calls a broken stitch successful.
4. Annotation objects remain editable until copy/export. Crop changes the document viewport; it does not overwrite the captured source.
5. Click-through pins must be recoverable from the menu bar, including hide/show all and restore-last-closed.
6. Multimodal tasks are provider-independent templates. Smart routing runs local OCR first and asks before cloud upload.
7. Apple Vision remains built in. PaddleOCR/RapidOCR is an optional downloaded enhanced engine because bundling a runtime by default conflicts with the lightweight macOS goal.

## Task 1: Long-capture matching and seam model

**Files:**
- Modify: `Sources/AIScreenshotCore/LongCapture/VerticalScrollMatcher.swift`
- Modify: `Sources/AIScreenshotCore/LongCapture/ScrollingImageStitcher.swift`
- Modify: `Tests/AIScreenshotCoreTests/VerticalScrollMatcherTests.swift`
- Modify: `Tests/AIScreenshotCoreTests/ScrollingImageStitcherTests.swift`

1. Add signed vertical displacement and direction to match results.
2. Add same-position sticky-top and sticky-bottom estimators with conservative maximum fractions.
3. Store stitch segments with direction, source crop, confidence, and a stable identifier.
4. Add quality issues for low confidence, rejected discontinuity, and output-size limits.
5. Add segmented rendering for maximum output height/pixels.
6. Test downward, upward, duplicates, sticky header/footer, unrelated frames, and multi-part output.

## Task 2: Long-capture runtime and review

**Files:**
- Modify: `Sources/AIScreenshotApp/Capture/ScrollingCaptureSessionController.swift`
- Create: `Sources/AIScreenshotApp/Capture/LongCaptureAutoScroller.swift`
- Create: `Sources/AIScreenshotApp/Editor/LongCaptureReviewWindowController.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`
- Modify: `Sources/AIScreenshotApp/System/ScreenCapturePermissionService.swift`

1. Add an opt-in auto-scroll button and Accessibility explanation.
2. Add resume/re-anchor after repeated discontinuities.
3. Finish into a review window instead of immediately treating every stitch as valid.
4. Display seam confidence and allow exclude/shift/reset per segment.
5. Export one image or numbered parts when CoreGraphics/file limits are reached.
6. Verify Safari, Chrome, WeChat, Codex, and WorkBuddy with fixed chat input regions.

## Task 3: Annotation document and tools

**Files:**
- Split/modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Create: `Sources/AIScreenshotApp/Editor/AnnotationDocument.swift`
- Create: `Sources/AIScreenshotApp/Editor/AnnotationCanvasView.swift`
- Add renderer tests in a new Core model/renderer test file where possible.

1. Add crop, numbered steps, highlighter, eraser, and magnifier.
2. Add select/move/resize/rotate for every vector object.
3. Add opacity, dash style, font size, fill/background, and reusable palettes.
4. Add undo/redo commands for property edits and viewport crop.
5. Render copy/export pixels and visually compare each tool.

## Task 4: Advanced pinned-image management

**Files:**
- Modify: `Sources/AIScreenshotApp/UI/PinnedImageWindowController.swift`
- Modify: `Sources/AIScreenshotApp/UI/MenuBarContentView.swift`
- Modify: `Sources/AIScreenshotApp/App/AppModel.swift`
- Create: `Sources/AIScreenshotApp/UI/PinManagerView.swift`

1. Crop the pin while retaining the original for reset.
2. Add click-through, thumbnail mode, groups, hide/show all, and restore-last-closed.
3. Add pin creation from clipboard image, text, HTML, color, and file URLs.
4. Ensure click-through pins remain recoverable from the menu bar.
5. Persist non-sensitive layout metadata only when the user enables restoration.

## Task 5: Multimodal task templates and smart routing

**Files:**
- Modify: `Sources/AIScreenshotCore/Models/CaptureModels.swift`
- Modify: `Sources/AIScreenshotCore/Recognition/OpenAICompatibleVisionClient.swift`
- Modify: `Sources/AIScreenshotApp/Recognition/MultimodalRecognitionService.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`
- Modify: `Sources/AIScreenshotApp/UI/SettingsView.swift`
- Modify: `Sources/AIScreenshotApp/UI/ModelSettingsView.swift`

1. Add task templates: general, exact OCR, translate, code, table, formula, UI explanation, and alt text.
2. Add OpenAI-compatible presets without storing provider secrets in defaults.
3. Add connection diagnostics that send no screenshot.
4. In smart mode, run local OCR and ask before low-confidence cloud enhancement.
5. Test request bodies, array/string responses, timeouts, cancellation, provider errors, and privacy branching.

## Task 6: OCR structure and engine adapters

**Files:**
- Modify: `Sources/AIScreenshotCore/OCR/VisionOCRService.swift`
- Create: `Sources/AIScreenshotCore/OCR/BarcodeRecognitionService.swift`
- Create: `Sources/AIScreenshotCore/OCR/DocumentRecognitionService.swift`
- Create: `Sources/AIScreenshotCore/OCR/ExternalOCREngine.swift`
- Modify: `Sources/AIScreenshotApp/UI/SettingsView.swift`

1. Add local barcode/QR recognition with Vision.
2. On supported macOS versions, add document recognition for paragraphs, lists, and tables; retain the existing text request as fallback.
3. Return structured table/document metadata alongside plain clipboard text.
4. Add formula-specific multimodal routing when local text confidence/geometry indicates math.
5. Define optional PaddleOCR/RapidOCR engine discovery, version manifest, checksum, install/uninstall, and fallback interfaces.
6. Ask for confirmation before downloading the enhanced engine pack and state its exact installed size.

## Task 7: Verification and release handoff

1. Run the complete unit suite after each task.
2. Build and stable-sign `artifacts/AI Screenshot.app`.
3. Perform real UI pixel/export verification for annotation and long capture.
4. Run the cross-app matrix and record exact failures, not optimistic status.
5. Update README, PRD, and verification docs only for proven behavior.
