# Inline Snipaste-style Annotation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep a captured region at its original screen position and provide an immediately usable annotation toolbar below it.

**Architecture:** Reuse `AnnotationCanvasView` inside a new full-screen borderless annotation panel. The capture coordinator owns the session lifecycle and commits rendered images to clipboard, save, or pin services only after the user chooses an exit action.

**Tech Stack:** Swift 6.2, AppKit, Core Graphics, Core Image, XCTest.

---

### Task 1: Make the annotation canvas reusable

**Files:**
- Modify: `Sources/AIScreenshotApp/Editor/AnnotationEditorWindowController.swift`
- Test: `Tests/AIScreenshotAppTests/InlineAnnotationLayoutTests.swift`

1. Expose `AnnotationTool` and `AnnotationCanvasView` within the app target.
2. Add a direct tool-selection method and configurable canvas image inset while retaining the popup-button adapter used by the existing editor.
3. Add a test proving the inline canvas maps the image edge-to-edge while the standalone editor retains its inset.
4. Run `swift test --filter InlineAnnotationLayoutTests` and expect PASS.

### Task 2: Build the full-screen inline annotation session

**Files:**
- Create: `Sources/AIScreenshotApp/Editor/InlineAnnotationController.swift`
- Test: `Tests/AIScreenshotAppTests/InlineAnnotationLayoutTests.swift`

1. Add pure toolbar placement logic and tests for below, above, and horizontal screen clamping.
2. Add a borderless screen-level panel with dimmed background and a canvas exactly covering the selected region.
3. Add compact direct tool buttons for selection, shapes, drawing, text, numbering, mosaic, blur, and crop; add color, width, undo, redo, copy, save, pin, cancel, and done actions.
4. Wire Escape/right-click to cancel and Enter to finish-and-copy.
5. Run the focused tests and expect PASS.

### Task 3: Integrate capture lifecycle and exports

**Files:**
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`
- Modify: `Sources/AIScreenshotApp/App/AppModel.swift` only if capture-state handoff requires it

1. Replace the `.edit` branch that opens the standalone editor with the inline session.
2. Keep `isCapturing` true until the inline session completes.
3. Route rendered results through existing clipboard, export, and pin services; return a truthful `CaptureOutcome` for every exit action.
4. Verify other quick actions are unchanged.

### Task 4: Verify and deliver

**Files:**
- Modify: `docs/alpha-verification.md`

1. Run `swift test` and expect 0 failures.
2. Build the release app with `scripts/build-app.sh` and verify its code signature.
3. Launch the release app, perform a real region capture, choose “标注,” and visually verify the original-position canvas, background mask, toolbar placement, and cancel path.
4. Record verified behavior and any remaining manual pixel checks in `docs/alpha-verification.md`.
