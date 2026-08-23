# PaddleOCR One-Click Enhancement Pack Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a real Apple Silicon PaddleOCR enhancement pack and let AI Screenshot install, validate, use, and remove it without requiring the user to manage Python or model files.

**Architecture:** The main App stays small and keeps Apple Vision as its built-in fallback. A separately built `paddleOCR` pack contains a self-contained arm64 Python runtime, PaddleOCR 3.x using its official ONNX Runtime engine, pinned PP-OCR mobile models, and a small adapter that implements the existing JSON process contract. `OptionalOCRPackManager` gains archive/catalog installation, progress, cancellation, health checking, and uninstall; the settings UI exposes one-click install while preserving manual directory import.

**Tech Stack:** Swift 6.2, SwiftUI, URLSession, CryptoKit, Foundation Archive/ditto, Python 3.12 arm64, PaddleOCR 3.x, ONNX Runtime CPU, PP-OCR mobile models.

---

### Task 1: Freeze the pack contract and security boundaries

**Files:**
- Modify: `Sources/AIScreenshotApp/Recognition/OptionalOCRPackManager.swift`
- Modify: `docs/ocr-enhancement-pack-spec.md`
- Create: `Tests/AIScreenshotAppTests/OptionalOCRPackManagerTests.swift`
- Modify: `Package.swift`

**Steps:**
1. Add public/internal manifest models with architecture, minimum macOS, archive SHA-256, size, and health-check metadata.
2. Add tests for engine mismatch, traversal, checksum mismatch, architecture mismatch, install replacement, and uninstall.
3. Implement validated staged installation and run tests.

### Task 2: Build the actual Apple Silicon PaddleOCR pack

**Files:**
- Create: `ocr-packs/paddleocr/adapter.py`
- Create: `ocr-packs/paddleocr/launcher.sh`
- Create: `ocr-packs/paddleocr/requirements-lock.txt`
- Create: `ocr-packs/paddleocr/catalog-template.json`
- Create: `scripts/build-paddleocr-pack.sh`
- Create: `scripts/test-paddleocr-pack.sh`

**Steps:**
1. Create an isolated arm64 runtime and install pinned PaddleOCR/ONNX dependencies.
2. Pre-fetch only the selected Chinese/English mobile OCR models.
3. Implement `--input … --output json` and `--health-check` responses.
4. Strip caches and development files, generate licenses/SBOM/checksums, and archive the directory.
5. Run the adapter on generated Chinese/English screenshot fixtures and verify non-empty text plus confidence.

### Task 3: Add one-click download/install to the App

**Files:**
- Modify: `Sources/AIScreenshotApp/Recognition/OptionalOCRPackManager.swift`
- Modify: `Sources/AIScreenshotApp/UI/SettingsView.swift`
- Modify: `Resources/Info.plist`

**Steps:**
1. Load the release catalog and select a package matching `arm64` and the current macOS.
2. Download with visible progress and cancellation, or resolve a signed local release artifact for development builds.
3. Verify the archive SHA-256 before extraction, reject links/path traversal, validate the inner manifest, health-check the adapter, and atomically replace the old version.
4. Show installed version, package size, install/update/remove actions, and clear failures in Settings.

### Task 4: End-to-end verification and release bundle

**Files:**
- Modify: `README.md`
- Modify: `docs/alpha-verification.md`
- Modify: `docs/ocr-enhancement-pack-spec.md`
- Modify: `scripts/build-app.sh`

**Steps:**
1. Run all Swift tests and pack contract tests.
2. Build the release App and verify code signing.
3. Install the generated PaddleOCR pack through the same manager path used by the UI.
4. OCR real Chinese/English fixtures, confirm `engine == paddleOCR`, then uninstall and confirm Apple Vision fallback.
5. Open Settings and visually verify idle, installing, installed, and error/recovery states.

## Acceptance criteria

- A user on Apple Silicon can click once to install without installing Python, Homebrew, Docker, or PaddlePaddle.
- No OCR image is uploaded; inference works with networking disabled after installation.
- An invalid checksum, wrong architecture, unsafe path, or failed health check cannot replace a working pack.
- PaddleOCR results identify the active engine as `paddleOCR`; removal immediately restores Apple Vision fallback.
- The separately distributed pack, archive checksum, version inventory, third-party licenses, and test evidence are present under `artifacts/`.
