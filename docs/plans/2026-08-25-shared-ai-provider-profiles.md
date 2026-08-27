# Shared AI Provider Profiles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use Code execution and verification guidance to implement this plan task-by-task.

**Goal:** Let users save multiple AI provider profiles, share them between AI recognition and screenshot translation, and migrate existing configuration and API keys without requiring re-entry.

**Architecture:** Persist non-secret profile metadata as versioned JSON in UserDefaults and store each API key in Keychain under a stable profile-specific account. Keep the legacy preference keys and Keychain accounts read-only for an idempotent first-run migration. AI recognition uses the active profile; translation stores a separate selected profile ID and only exposes profiles that contain both text and vision models plus a saved key.

**Tech Stack:** Swift 6, SwiftUI, UserDefaults, macOS Keychain, XCTest, URLSession mock protocol.

---

### Task 1: Add profile storage and migration

**Files:**
- Create: `Sources/AIScreenshotApp/Models/AIProviderProfile.swift`
- Create: `Sources/AIScreenshotApp/System/AIProviderProfileStore.swift`
- Modify: `Sources/AIScreenshotApp/System/PersistentConfigurationIdentity.swift`
- Test: `Tests/AIScreenshotAppTests/AIProviderProfileStoreTests.swift`

**Steps:**
1. Write tests for JSON persistence, active/translation selection, eligibility, stable profile key accounts, and idempotent legacy migration.
2. Run the focused tests and verify they fail.
3. Implement the versioned profile store and migration from both legacy AI and legacy translation settings/Keychain accounts.
4. Run focused tests and verify they pass.

### Task 2: Route recognition and translation through profiles

**Files:**
- Modify: `Sources/AIScreenshotApp/Recognition/MultimodalRecognitionService.swift`
- Modify: `Sources/AIScreenshotApp/Recognition/ScreenshotTranslationService.swift`
- Modify: `Sources/AIScreenshotCore/Recognition/TranslationProviderClient.swift`
- Modify: `Sources/AIScreenshotApp/Capture/CaptureCoordinator.swift`
- Test: `Tests/AIScreenshotCoreTests/TranslationProviderClientTests.swift`
- Test: `Tests/AIScreenshotAppTests/AIProviderProfileStoreTests.swift`

**Steps:**
1. Add failing request-shape tests for Azure, Anthropic, and Gemini translation.
2. Add provider-aware text, segment, and image translation requests.
3. Load active and translation-selected profiles in services, including profile-specific keys.
4. Keep precise user-facing errors when no eligible profile is selected.
5. Run focused service/client tests.

### Task 3: Redesign AI model settings for multiple profiles

**Files:**
- Modify: `Sources/AIScreenshotApp/UI/ModelSettingsView.swift`
- Modify: `Tests/AIScreenshotAppTests/ModelSettingsExperienceTests.swift`

**Steps:**
1. Add a profile list/sidebar with add, duplicate, rename, delete, and active-selection behavior.
2. Reuse the guided setup cards as the profile editor.
3. Require a text model for translation eligibility and record successful vision verification.
4. Preserve migration messaging and make profile status visible.
5. Run UI model tests and compile.

### Task 4: Simplify translation settings

**Files:**
- Modify: `Sources/AIScreenshotApp/UI/TranslationSettingsView.swift`
- Modify: `Sources/AIScreenshotApp/Models/TranslationConfiguration.swift`
- Test: `Tests/AIScreenshotAppTests/TranslationConfigurationTests.swift`

**Steps:**
1. Replace duplicate endpoint/model/key fields with a Picker of eligible shared profiles.
2. Keep only source/target language, default mode, and visual fallback preferences.
3. Add a clear empty state linking users conceptually to AI model settings.
4. Add compatibility tests for language/default-mode persistence.

### Task 5: Verify and package locally

**Files:**
- Modify only files needed for test/build fixes.

**Steps:**
1. Run focused tests for migration and provider request shapes.
2. Run the complete Swift test suite.
3. Build the app artifact.
4. Launch the local app and inspect both settings pages without changing external state.
5. Report remaining manual checks; do not push or replace a release unless requested.
