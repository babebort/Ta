# Ta CLI Annotation Transform Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose deterministic, local, recipe-driven annotation editing through `ta transform`, including crop, shapes, drawing, text, number badges, mosaic, blur, eraser, magnifier, undo, and redo.

**Architecture:** Add versioned recipe contracts and validation, render the recipe in the app Bridge with a vector editing session and snapshot history, and expose the existing reserved `transform.image` method through the CLI. Each transform is atomic and returns a rendered PNG Artifact while retaining vector state for undo/redo.

**Tech Stack:** Swift 6.2, AppKit/Core Graphics, Core Image, Swift Testing/XCTest, the existing Ta Agent Bridge and CLI.

---

### Task 1: Define and validate the annotation recipe contract

**Files:**
- Create: `Sources/TaAgentContracts/AnnotationRecipe.swift`
- Create: `Tests/TaAgentContractsTests/AnnotationRecipeTests.swift`

**Steps:**

1. Write failing decode tests for every operation type and `#RRGGBB` / `#RRGGBBAA` colors.
2. Write failing validation tests for unsupported versions, duplicate IDs, crop ordering, missing eraser targets, empty paths, and non-positive geometry.
3. Run `swift test --filter AnnotationRecipeTests` and confirm the new types are missing.
4. Implement `AnnotationRecipe`, operation payloads, geometry/color values, decoding, and deterministic validation errors.
5. Re-run `swift test --filter AnnotationRecipeTests` and confirm all recipe tests pass.

### Task 2: Implement local vector-session rendering and history

**Files:**
- Create: `Sources/AIScreenshotApp/Agent/TaAgentAnnotationRenderer.swift`
- Create: `Sources/AIScreenshotApp/Agent/TaAgentAnnotationSession.swift`
- Create: `Tests/AIScreenshotAppTests/TaAgentAnnotationRendererTests.swift`
- Create: `Tests/AIScreenshotAppTests/TaAgentAnnotationSessionTests.swift`

**Steps:**

1. Write failing tests for crop size and pixel changes produced by rectangle, ellipse, arrow, pen, highlighter, text, number, mosaic rectangle/brush, blur, and magnify.
2. Write failing session tests for atomic recipe application, erasing by ID, 100-entry history, undo, redo, and redo invalidation after a new operation.
3. Run the two new test classes and confirm no renderer/session exists.
4. Implement vector elements and a renderer using top-left recipe coordinates converted to AppKit drawing coordinates.
5. Implement Core Image mosaic/blur and clipped source-image magnification.
6. Implement snapshot-based session history and atomic recipe application.
7. Re-run the new tests and inspect any generated fixture images when pixel assertions fail.

### Task 3: Expose `transform.image` through the Bridge

**Files:**
- Modify: `Sources/AIScreenshotApp/Agent/TaAgentCapabilityService.swift`
- Modify: `Tests/AIScreenshotAppTests/TaAgentCapabilityServiceTests.swift`

**Steps:**

1. Write failing service tests asserting `transform.image` is advertised and supports `apply`, `undo`, and `redo` actions.
2. Assert successful requests return a non-empty PNG Artifact, updated dimensions, operation count, history flags, and `cloudUploaded == false`.
3. Assert invalid recipes do not mutate the current edit session.
4. Run `swift test --filter TaAgentCapabilityServiceTests` and confirm the unsupported-method failure.
5. Add `transform.image` dispatch, recipe decoding, session reset on new capture/input, rendering, and Artifact storage.
6. Re-run the capability tests.

### Task 4: Add `ta transform` CLI parsing and output

**Files:**
- Modify: `Sources/TaCLI/CLIParser.swift`
- Modify: `Sources/TaCLI/CLICommands.swift`
- Modify: `Tests/TaCLITests/CLIParserTests.swift`
- Modify: `Tests/TaCLITests/CLIGoldenOutputTests.swift`

**Steps:**

1. Write failing parser tests for `transform last --recipe`, explicit input paths, `transform undo`, `transform redo`, `--output`, missing recipe, and unexpected arguments.
2. Run `swift test --filter TaCLITests` and confirm the command is unknown.
3. Implement parser mapping to `transform.image` with `action=apply|undo|redo`; read recipe contents in the runner so the Bridge never receives an arbitrary recipe path.
4. Reuse the existing output-save pipeline for returned artifacts.
5. Update usage and human-readable output.
6. Run `swift test --filter TaCLITests` and confirm CLI tests pass.

### Task 5: Document and verify the complete local workflow

**Files:**
- Modify: `docs/agent-integration.md`
- Modify: `Integrations/AgentSkill/ta/references/commands.md`
- Modify: `Integrations/AgentSkill/ta/references/editing-recipes.md`
- Create: `Tests/Fixtures/annotation-recipe-v1.json`

**Steps:**

1. Document the exact command syntax, schema, coordinate system, operation fields, local-only behavior, and undo/redo semantics.
2. Add a fixture recipe containing crop, rectangle, arrow, highlighter, Chinese text, number, mosaic, blur, and magnify.
3. Run `swift test --filter AnnotationRecipeTests`.
4. Run `swift test --filter TaAgentAnnotation`.
5. Run `swift test --filter TaAgentCapabilityServiceTests`.
6. Run `swift test --filter TaCLITests`.
7. Run the full `swift test --disable-sandbox` suite with module caches under `/tmp`.
8. Build the app/CLI, launch the current app Bridge, capture a non-sensitive test window, and run `ta transform` with the fixture recipe.
9. Verify the response has `ok: true`, a non-empty PNG Artifact, `meta.cloudUploaded: false`, and the durable output exists with the expected dimensions.
10. Visually inspect the marked image for arrow direction, Chinese text, crop, mosaic/blur, and magnifier clipping.
