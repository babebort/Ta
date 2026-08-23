# AI Screenshot Alpha Capture/OCR Implementation Plan

> **For Codex:** Implement this plan task-by-task using the Code workflow. The current folder is not a Git repository, so commit steps are intentionally omitted until repository initialization is explicitly requested.

**Goal:** Build a runnable macOS Alpha that lives in the menu bar and completes the shortest path: global shortcut → region selection → local OCR → guarded clipboard write → non-activating result capsule.

**Architecture:** Use a native Swift 6 package with a reusable `AIScreenshotCore` library and a SwiftUI/AppKit executable. AppKit owns global hotkeys, selection overlays and non-activating panels; ScreenCaptureKit captures pixels; Vision performs on-device OCR; Keychain stores optional provider secrets. Keep cloud AI out of the critical path.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Carbon hotkeys, ScreenCaptureKit, Vision, Security/Keychain, XCTest/Swift Testing, Swift Package Manager.

---

## Task 1: Scaffold the project

**Files:**

- Create: `Package.swift`
- Create: `Sources/AIScreenshotCore/AIScreenshotCore.swift`
- Create: `Sources/AIScreenshotApp/AIScreenshotApp.swift`
- Create: `Tests/AIScreenshotCoreTests/AIScreenshotCoreTests.swift`
- Create: `.gitignore`

**Steps:**

1. Create a macOS 14 Swift package with one library, one executable and one test target.
2. Add minimal `@main` SwiftUI menu-bar app code.
3. Add a failing smoke test importing `AIScreenshotCore`.
4. Run `swift test` and confirm the initial failure.
5. Add the minimal core symbol and rerun until it passes.

## Task 2: Build the deterministic core

**Files:**

- Create: `Sources/AIScreenshotCore/Models/CaptureModels.swift`
- Create: `Sources/AIScreenshotCore/OCR/ContentClassifier.swift`
- Create: `Sources/AIScreenshotCore/OCR/OCRTextNormalizer.swift`
- Create: `Sources/AIScreenshotCore/Clipboard/ClipboardCommitPolicy.swift`
- Modify: `Tests/AIScreenshotCoreTests/AIScreenshotCoreTests.swift`

**Steps:**

1. Write tests for capture job state, text/code/table/QR classification and line normalization.
2. Run the tests and confirm failures.
3. Implement small value types and pure classification/normalization functions.
4. Add clipboard policy tests proving an old job cannot overwrite a newer user copy.
5. Run `swift test` and require all core tests to pass.

## Task 3: Add menu bar, settings and global hotkeys

**Files:**

- Create: `Sources/AIScreenshotApp/App/AppModel.swift`
- Create: `Sources/AIScreenshotApp/UI/MenuBarContentView.swift`
- Create: `Sources/AIScreenshotApp/UI/SettingsView.swift`
- Create: `Sources/AIScreenshotApp/System/GlobalHotKeyManager.swift`
- Modify: `Sources/AIScreenshotApp/AIScreenshotApp.swift`

**Steps:**

1. Build a Typeless-like compact menu with Intelligent Capture, Image Capture and Settings.
2. Register intelligent/image shortcuts with Carbon rather than monitoring every key.
3. Route menu actions and shortcuts through `AppModel`.
4. Add settings for result-capsule duration and OCR languages.
5. Run `swift build` and fix all Swift 6 concurrency errors.

## Task 4: Implement region selection and pixel capture

**Files:**

- Create: `Sources/AIScreenshotApp/Capture/SelectionOverlayController.swift`
- Create: `Sources/AIScreenshotApp/Capture/SelectionOverlayView.swift`
- Create: `Sources/AIScreenshotApp/Capture/ScreenCaptureService.swift`
- Create: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`

**Steps:**

1. Present one transparent, borderless overlay on the pointer's display.
2. Support drag-to-select, live dimensions and Escape cancellation.
3. Convert AppKit point coordinates to ScreenCaptureKit display-local coordinates.
4. Capture the selected region with `SCScreenshotManager`, excluding this application.
5. Prove cancellation never changes the clipboard.

## Task 5: Implement local OCR and guarded clipboard writes

**Files:**

- Create: `Sources/AIScreenshotApp/OCR/VisionOCRService.swift`
- Create: `Sources/AIScreenshotApp/System/ClipboardService.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`

**Steps:**

1. Run accurate Vision OCR with Simplified Chinese and English recognition.
2. Sort observations into reading order and pass text through the core normalizer/classifier.
3. Capture pasteboard `changeCount` before OCR.
4. Commit text only when the user has not copied something else during processing.
5. If OCR finds no text, copy the original PNG instead.
6. Run `swift test` and `swift build`.

## Task 6: Add the non-activating result capsule

**Files:**

- Create: `Sources/AIScreenshotApp/UI/ResultBarController.swift`
- Create: `Sources/AIScreenshotApp/UI/ResultBarView.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`

**Steps:**

1. Create a borderless `NSPanel` using the non-activating style.
2. Display local-processing, copied-text, copied-image, low-confidence and clipboard-changed states.
3. Auto-hide successful results after the configured duration; retain actionable errors.
4. Ensure the panel never becomes the key window and does not steal typing focus.
5. Build and launch for visual inspection.

## Task 7: Add provider settings and Keychain boundary

**Files:**

- Create: `Sources/AIScreenshotApp/Models/ProviderConfiguration.swift`
- Create: `Sources/AIScreenshotApp/System/KeychainSecretStore.swift`
- Create: `Sources/AIScreenshotApp/UI/ModelSettingsView.swift`
- Modify: `Sources/AIScreenshotApp/UI/SettingsView.swift`

**Steps:**

1. Store Base URL and model names as non-secret preferences.
2. Store API Key only as a Generic Password in Keychain.
3. Display only an availability indicator and masked state, never the secret.
4. Export no Key and log no Key.
5. Add unit-testable validation for HTTPS versus localhost URLs.

## Task 8: Verify and document the Alpha

**Files:**

- Create: `README.md`
- Create: `docs/alpha-verification.md`

**Steps:**

1. Run `swift test` and require a clean pass.
2. Run `swift build -c release` and require a clean build.
3. Launch the executable and inspect menu bar, selection overlay and result capsule.
4. Manually verify text capture into Notes and image fallback for a non-text region.
5. Record what is implemented, permission steps, known limitations and the next milestone.

---

## Alpha exit criteria

- Core feature tests pass.
- Release configuration builds without errors.
- Global shortcut works without Accessibility permission.
- Escape cancellation leaves the previous clipboard untouched.
- A clear Chinese/English region is copied as text using on-device OCR.
- A region with no text is copied as PNG.
- The result capsule reports state without stealing focus.
- No API Key appears outside Keychain.
- Long capture, advanced annotation and beautification remain explicitly scheduled for the following milestones rather than partially faked in this Alpha.
