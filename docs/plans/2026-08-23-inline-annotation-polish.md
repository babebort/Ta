# Inline Annotation Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Polish the Snipaste-style annotation toolbar, add WeChat-style tapered arrows, support both rectangular and brush mosaic workflows, and make pinned images disappear on double-click.

**Architecture:** Keep the existing canvas and inline panel lifecycle. Add reusable arrow geometry and a mosaic-stroke annotation element, then refine the AppKit toolbar with explicit icons, larger hit targets, clear selected states, and tool-dependent cursor feedback.

**Tech Stack:** Swift 6.2, AppKit, Core Graphics, Core Image, XCTest.

---

### Task 1: Tapered arrow geometry

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Test: `Tests/AIScreenshotAppTests/AnnotationDrawingTests.swift`

1. Add tests asserting a seven-point arrow polygon has a smaller tail width than its head-base width and keeps the supplied endpoint as its tip.
2. Implement reusable tapered-arrow geometry with short-arrow bounds.
3. Replace the stroked line arrow renderer with a filled polygon renderer.
4. Run `swift test --filter AnnotationDrawingTests` and expect PASS.

### Task 2: Brush mosaic model and renderer

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Test: `Tests/AIScreenshotAppTests/AnnotationDrawingTests.swift`

1. Add `mosaicBrush` to the tool model and a mosaic-stroke element containing points and width.
2. Collect points while dragging, preview the path, and commit it to undo history on mouse up.
3. Clip the drawing context to a round-cap stroked path before drawing the pixelated source.
4. Extend hit testing, moving, scaling, and export rendering for the new element.
5. Run focused tests and expect PASS.

### Task 3: Toolbar visual and interaction polish

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/InlineAnnotationController.swift`
- Modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`

1. Increase icon button hit targets to 36×34 points and constrain symbol size to 15 points.
2. Add consistent background, border, hover-safe image scaling, and a strong accent selected state.
3. Replace the cursor arrow with a hand selection icon and the ambiguous format symbol with a literal `T` button.
4. Disable selection until an annotation exists; enable it through a canvas element-change callback.
5. Add cursor feedback for selection, text, eraser, and drawing tools.

### Task 4: Pinned-image double-click close

**Files:**
- Modify: `Sources/AIScreenshotApp/UI/PinnedImageWindowController.swift`
- Test: `Tests/AIScreenshotAppTests/PinnedImageInteractionTests.swift`

1. Make the non-activating pinned-image view accept the first mouse event.
2. Treat click counts of two or more as close in both mouse-down and mouse-up handling, with an idempotence guard.
3. Keep the existing recoverable-close stack unchanged.
4. Add single-click and double-click decision regression tests.

### Task 5: Verification and release

**Files:**
- Modify: `docs/alpha-verification.md`

1. Run focused and full Swift tests with 0 failures.
2. Build and sign the Release app.
3. Use the inline-editor smoke fixture to visually verify the toolbar, tapered arrow, rectangular mosaic, brush mosaic, text tool, undo, pin action, and pinned-image double-click close.
4. Record the verified behavior and restart the normal app for user testing.
