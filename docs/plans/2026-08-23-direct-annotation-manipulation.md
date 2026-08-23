# Direct Annotation Manipulation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make inline annotation compact and directly editable, with non-blocking in-canvas text entry, brush mosaic, object dragging, and corner resizing.

**Architecture:** Keep `AnnotationCanvasView` as the single source of truth. Replace modal text alerts with an embedded text field, route pointer input through a reusable direct-manipulation state, and apply uniform transforms around the opposite selection handle to every annotation element type.

**Tech Stack:** Swift 6.2, AppKit, Core Graphics, Core Image, XCTest.

---

### Task 1: Compact toolbar metrics

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/InlineAnnotationController.swift`
- Test: `Tests/AIScreenshotAppTests/InlineAnnotationLayoutTests.swift`

1. Extract toolbar button and symbol dimensions into testable metrics.
2. Add tests for 32×30 point buttons and 12 point symbols.
3. Reduce spacing, edge insets, color well, slider, and completion button proportionally.
4. Run the focused layout tests.

### Task 2: Non-modal in-canvas text entry

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Test: `Tests/AIScreenshotAppTests/InlineAnnotationLayoutTests.swift`

1. Add a canvas-owned `NSTextField` positioned from image coordinates.
2. Submit on Return or non-empty focus loss; cancel only the text entry on Escape.
3. Reuse the field to edit existing text on double-click.
4. Remove `NSAlert.runModal()` from the inline text path.
5. Verify that selecting text no longer blocks the screen-saver-level editor panel.

### Task 3: Direct move and corner resize

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Test: `Tests/AIScreenshotAppTests/AnnotationDrawingTests.swift`

1. Add tests for opposite-corner anchoring and uniform scale-factor projection.
2. Hit-test the four visible selection handles before tool-specific input.
3. Select and move any existing object without requiring the hand tool.
4. Scale every annotation element around the opposite corner, including mosaic strokes and text.
5. Keep newly created objects selected and retain their visible handles.

### Task 4: Brush mosaic verification

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/InlineAnnotationController.swift`
- Modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Test: `Tests/AIScreenshotAppTests/AnnotationDrawingTests.swift`

1. Keep rectangular mosaic and brush mosaic as explicit tools.
2. Make the brush tooltip and icon unambiguous.
3. Verify continuous point collection, round-cap clipping, width adjustment, movement, and resize.

### Task 5: Full verification and release

**Files:**
- Modify: `docs/alpha-verification.md`

1. Run focused tests and the full Swift test suite with zero failures.
2. Build and sign `artifacts/AI Screenshot.app`.
3. Use the inline-editor smoke fixture to verify compact toolbar, in-canvas text, brush mosaic, direct movement, and corner resizing.
4. Restart the normal Release App for user testing.
