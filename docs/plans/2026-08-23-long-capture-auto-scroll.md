# Long Capture Auto-Scroll and Preview Orientation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent automatic long capture from stopping after roughly two scrolls and ensure stitched previews display top-to-bottom rather than upside down.

**Architecture:** Replace capture-tick duplicate counting with a small, independently testable auto-scroll progress tracker that counts unsuccessful scroll attempts. Keep the stitcher's logical strips ordered from document top to bottom, map those rows explicitly into Quartz's bottom-origin output canvas, and restore the user's pointer after globally posting a compatible synthetic scroll event.

**Tech Stack:** Swift 6.2, Swift Concurrency, ScreenCaptureKit, CoreGraphics, XCTest.

---

### Task 1: Lock the failure modes with tests

**Files:**
- Create: `Sources/AIScreenshotCore/LongCapture/AutoScrollProgressTracker.swift`
- Create: `Tests/AIScreenshotCoreTests/AutoScrollProgressTrackerTests.swift`
- Modify: `Tests/AIScreenshotCoreTests/ScrollingImageStitcherTests.swift`

1. Add tests proving duplicate capture ticks do not independently consume the stop budget.
2. Add tests proving a successful appended frame resets all no-progress attempts.
3. Add a test proving the tracker stops only after six actual scroll attempts without progress.
4. Add asymmetric top/bottom pixel tests for single-frame, downward-stitched, and segmented output.
5. Run the focused tests and confirm the orientation test fails against the old renderer.

### Task 2: Implement robust automatic scrolling

**Files:**
- Modify: `Sources/AIScreenshotApp/Capture/ScrollingCaptureSessionController.swift`
- Modify: `Sources/AIScreenshotApp/System/AccessibilityAutoScrollService.swift`
- Modify: `Sources/AIScreenshotCore/LongCapture/AutoScrollProgressTracker.swift`

1. Feed accepted/duplicate/rejected dispositions into the progress tracker.
2. Fire scrolls on a minimum 700 ms interval rather than every second capture tick.
3. Count no progress only when another scroll is actually sent.
4. Stop after six no-progress attempts and show a precise bottom-detection message.
5. Compute a selection-relative distance clamped to 180–520 pixels, post a short continuous scroll gesture at the selection center, and safely restore the user's pointer without overwriting concurrent mouse movement.

### Task 3: Fix stitched-image orientation

**Files:**
- Modify: `Sources/AIScreenshotCore/LongCapture/ScrollingImageStitcher.swift`

1. Avoid an output-wide canvas flip, which makes the final AppKit/PNG representation upside down.
2. Convert each top-origin strip range into the reversed Quartz destination Y so strip order remains top-to-bottom.
3. Validate visual orientation through the same AppKit PNG encoding path used by preview/save.
4. Run orientation, stitching, reverse-scroll, and segmentation tests.

### Task 4: Verify and package

**Files:**
- Modify: `docs/alpha-verification.md`
- Rebuild: `artifacts/AI Screenshot.app`

1. Run all Swift tests and confirm zero failures.
2. Build and verify the signed release App.
3. Launch the long-capture UI and verify the HUD offers automatic scrolling.
4. Record remaining real-App matrix checks for WeChat, browser, Codex, and WorkBuddy.

## Acceptance criteria

- Two slow or duplicate scroll responses cannot stop automatic capture.
- Successful content movement always resets bottom detection.
- Bottom detection requires six sent scrolls with no added page content.
- Preview and exported images have the document top at the visual top.
- Manual up/down scrolling, fixed-edge removal, seam review, and 30,000-pixel segmentation keep passing existing tests.
