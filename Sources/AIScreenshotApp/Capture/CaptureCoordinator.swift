import AppKit
import AIScreenshotCore

enum CaptureOutcome {
    case cancelled
    case completed(String)
    case failed(String)
}

@MainActor
final class CaptureCoordinator {
    private let selectionOverlay = SelectionOverlayController()
    private let captureService = ScreenCaptureService()
    private let ocrService = ConfiguredOCRService()
    private let clipboardService = ClipboardService()
    private let resultBar = ResultBarController()
    private let pinnedImageWindows = PinnedImageWindowController()
    private let scrollingCaptureSession = ScrollingCaptureSessionController()
    private let imageExportService = ImageExportService()
    private let annotationEditor = AnnotationEditorWindowController()
    private let inlineAnnotation = InlineAnnotationController()
    private let multimodalRecognitionService = MultimodalRecognitionService()
    private let translationService = ScreenshotTranslationService()
    private let translationRenderer = TranslatedImageRenderer()
    private let translationOCR = VisionOCRService()

    private var processingTask: Task<Void, Never>?
    private var latestJobID: UUID?

    func pinClipboardContent() -> Bool { pinnedImageWindows.pinFromPasteboard() }
    func hideAllPins() { pinnedImageWindows.hideAll() }
    func showAllPins() { pinnedImageWindows.showAll() }
    func enableAllPinInteraction() { pinnedImageWindows.enableInteractionForAll() }
    func restoreLastClosedPin() -> Bool { pinnedImageWindows.restoreLastClosed() }

    func openEditorSmokeFixture() {
        guard let image = makeSmokeFixtureImage() else { return }
        annotationEditor.open(image: image)
    }

    func openInlineEditorSmokeFixture(completion: @escaping () -> Void) {
        guard let image = makeSmokeFixtureImage(),
              let screen = NSScreen.main ?? NSScreen.screens.first,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            completion()
            return
        }
        let scale = min(
            min(860, screen.frame.width * 0.72) / CGFloat(image.width),
            min(480, screen.frame.height * 0.58) / CGFloat(image.height)
        )
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        let selection = CaptureSelection(
            globalRect: CGRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.midY - height / 2 + 40,
                width: width,
                height: height
            ),
            screenFrame: screen.frame,
            displayID: CGDirectDisplayID(screenNumber.uint32Value),
            backingScaleFactor: screen.backingScaleFactor
        )
        inlineAnnotation.open(
            image: image,
            selection: selection,
            actionHandler: { [weak self] action, renderedImage in
                guard let self else { return false }
                switch action {
                case .copy:
                    return clipboardService.copyImage(
                        renderedImage,
                        initialChangeCount: clipboardService.changeCount,
                        jobIsLatest: true
                    )
                case .save:
                    return (try? imageExportService.save(renderedImage)) != nil
                case .pin:
                    pinnedImageWindows.pin(renderedImage, near: selection)
                    return true
                }
            },
            completion: { _ in completion() }
        )
    }

    func openCaptureToolbarSmokeFixture(completion: @escaping () -> Void) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            completion()
            return
        }
        let size = screen.frame.size
        let selection = CGRect(
            x: size.width * 0.18,
            y: size.height * 0.34,
            width: size.width * 0.64,
            height: size.height * 0.42
        )
        selectionOverlay.begin(showsActionToolbar: true, presetRect: selection) { _, _ in
            completion()
        }
    }

    func openResultBarSmokeFixture(kind: ResultBarKind) {
        let state = switch kind {
        case .processing:
            ResultBarState(kind: .processing, title: "Recognizing image…", detail: "Processed locally, nothing is uploaded")
        case .success:
            ResultBarState(kind: .success, title: "Image copied", detail: "910 × 358")
        case .warning:
            ResultBarState(kind: .warning, title: "Copied, some text may be inaccurate", detail: "Please check the recognized result")
        case .failure:
            ResultBarState(kind: .failure, title: "Copy failed", detail: "Clipboard is in use by another app")
        }
        resultBar.show(state, autoHide: false, dismissalOverrideSeconds: 60)
    }

    private func makeSmokeFixtureImage() -> CGImage? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 620,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 620).fill()
        "Ta · Annotation Sample".draw(at: CGPoint(x: 60, y: 470), withAttributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: NSColor.black
        ])
        "Arrow · Text · Highlight · Mosaic · Free Resize".draw(at: CGPoint(x: 60, y: 390), withAttributes: [
            .font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.darkGray
        ])
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 90, width: 880, height: 220), xRadius: 24, yRadius: 24).fill()
        NSGraphicsContext.restoreGraphicsState()
        return representation.cgImage
    }

    func start(mode: CaptureMode, completion: @escaping (CaptureOutcome) -> Void) {
        processingTask?.cancel()

        guard ensureScreenCapturePermission(completion: completion) else {
            return
        }

        if mode == .long {
            startLongCapture(completion: completion)
            return
        }

        let jobID = UUID()
        latestJobID = jobID
        let initialChangeCount = clipboardService.changeCount
        let configuredAction = action(for: mode)
        guard let overlayContext = selectionOverlay.prepareStartContext() else {
            completion(.failed("Could not find the display"))
            return
        }

        // Change the pointer as soon as the shortcut is handled. The overlay is
        // shown only after the full display frame has been captured, so the user
        // always selects from the shortcut-time image rather than a live page.
        NSCursor.crosshair.set()
        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let frozenDisplayImage = try await captureService.captureDisplay(
                    displayID: overlayContext.displayID,
                    pixelScale: overlayContext.screen.backingScaleFactor,
                    showsCursor: false
                )
                try Task.checkCancellation()
                guard latestJobID == jobID else { return }

                selectionOverlay.begin(
                    context: overlayContext,
                    frozenDisplayImage: frozenDisplayImage,
                    showsActionToolbar: configuredAction == nil
                ) { [weak self] selection, selectedAction in
                    guard let self else { return }
                    guard let selection else {
                        completion(.cancelled)
                        return
                    }

                    let action = selectedAction ?? configuredAction ?? .copyImage
                    UserDefaults.standard.set(action.rawValue, forKey: "lastPostCaptureQuickAction")

                    processingTask = Task { [weak self] in
                        guard let self else { return }
                        await process(
                            jobID: jobID,
                            action: action,
                            selection: selection,
                            initialChangeCount: initialChangeCount,
                            completion: completion
                        )
                    }
                }
            } catch is CancellationError {
                NSCursor.arrow.set()
                completion(.cancelled)
            } catch {
                NSCursor.arrow.set()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                resultBar.show(
                    ResultBarState(kind: .failure, title: "Failed to prepare the screenshot", detail: message),
                    autoHide: false
                )
                completion(.failed("Failed to prepare the screenshot"))
            }
        }
    }

    func startFixedTestRegion(
        mode: CaptureMode,
        completion: @escaping (CaptureOutcome) -> Void
    ) {
        guard ensureScreenCapturePermission(completion: completion) else {
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            completion(.failed("Could not find the display"))
            return
        }

        processingTask?.cancel()
        let jobID = UUID()
        latestJobID = jobID
        let initialChangeCount = clipboardService.changeCount
        let action = action(for: mode) ?? .localOCR
        let frame = screen.frame
        let selection = CaptureSelection(
            globalRect: CGRect(
                x: frame.minX + frame.width * 0.12,
                y: frame.maxY - min(280, frame.height * 0.36),
                width: min(680, frame.width * 0.58),
                height: min(210, frame.height * 0.28)
            ),
            screenFrame: frame,
            displayID: CGDirectDisplayID(screenNumber.uint32Value),
            backingScaleFactor: screen.backingScaleFactor
        )

        processingTask = Task { [weak self] in
            guard let self else { return }
            await process(
                jobID: jobID,
                action: action,
                selection: selection,
                initialChangeCount: initialChangeCount,
                completion: completion
            )
        }
    }

    private func process(
        jobID: UUID,
        action: CaptureQuickAction,
        selection: CaptureSelection,
        initialChangeCount: Int,
        completion: @escaping (CaptureOutcome) -> Void
    ) async {
        let shouldDismissDeferredOverlay = action == .edit
        defer {
            if shouldDismissDeferredOverlay {
                selectionOverlay.dismiss()
            }
        }
        do {
            try Task.checkCancellation()
            let image = try await captureService.capture(selection)
            try Task.checkCancellation()

            if action == .copyImage {
                let committed = clipboardService.copyImage(
                    image,
                    initialChangeCount: initialChangeCount,
                    jobIsLatest: latestJobID == jobID
                )
                if committed {
                    resultBar.show(
                        ResultBarState(kind: .success, title: "Image copied", detail: "\(image.width) × \(image.height)"),
                        autoHide: true
                    )
                    completion(.completed("Image copied"))
                } else {
                    showClipboardChanged(completion: completion)
                }
                return
            }

            if action == .pin {
                pinnedImageWindows.pin(image, near: selection)
                resultBar.show(
                    ResultBarState(
                        kind: .success,
                        title: "Pinned to screen",
                        detail: "Drag to move · scroll to zoom · ⌘+scroll to adjust opacity · double-click to close"
                    ),
                    autoHide: true
                )
                completion(.completed("Pinned"))
                return
            }

            if action == .multimodal {
                resultBar.show(
                    ResultBarState(
                        kind: .processing,
                        title: "Calling the multimodal model…",
                        detail: "Only the image from this selection is uploaded"
                    ),
                    autoHide: false
                )
                do {
                    let text = try await multimodalRecognitionService.recognize(image: image)
                    try Task.checkCancellation()
                    let committed = clipboardService.copyText(
                        text,
                        initialChangeCount: initialChangeCount,
                        jobIsLatest: latestJobID == jobID
                    )
                    if committed {
                        resultBar.show(
                            ResultBarState(
                                kind: .success,
                                title: "AI recognition result copied",
                                detail: "\(text.count) characters · \(multimodalRecognitionService.activeVisionModelName)"
                            ),
                            autoHide: true
                        )
                        completion(.completed("AI recognition result copied"))
                    } else {
                        showClipboardChanged(completion: completion)
                    }
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    resultBar.show(
                        ResultBarState(kind: .failure, title: "AI recognition failed", detail: message),
                        autoHide: false
                    )
                    completion(.failed("AI recognition failed"))
                }
                return
            }

            if action == .translate || action == .translateText {
                let configuration = TranslationConfiguration.load()
                guard let mode = TranslationModeRouting.mode(
                    for: action,
                    configuredDefault: configuration.defaultMode
                ) else {
                    completion(.cancelled)
                    return
                }
                do {
                    try await performTranslation(
                        image: image,
                        mode: mode,
                        initialChangeCount: initialChangeCount,
                        jobID: jobID,
                        completion: completion
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    resultBar.show(
                        ResultBarState(kind: .failure, title: "Screenshot translation failed", detail: message),
                        autoHide: false
                    )
                    completion(.failed("Screenshot translation failed"))
                }
                return
            }

            if action == .save {
                do {
                    if let url = try imageExportService.save(image) {
                        resultBar.show(
                            ResultBarState(
                                kind: .success,
                                title: "Screenshot saved",
                                detail: url.lastPathComponent
                            ),
                            autoHide: true
                        )
                        completion(.completed("Screenshot saved"))
                    } else {
                        completion(.cancelled)
                    }
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    resultBar.show(
                        ResultBarState(kind: .failure, title: "Save failed", detail: message),
                        autoHide: false
                    )
                    completion(.failed("Save failed"))
                }
                return
            }

            if action == .edit {
                var savedFilename: String?
                inlineAnnotation.open(
                    image: image,
                    selection: selection,
                    actionHandler: { [weak self] inlineAction, renderedImage in
                        guard let self else { return false }
                        switch inlineAction {
                        case .copy:
                            return clipboardService.copyImage(
                                renderedImage,
                                initialChangeCount: clipboardService.changeCount,
                                jobIsLatest: latestJobID == jobID
                            )
                        case .save:
                            do {
                                guard let url = try imageExportService.save(renderedImage) else { return false }
                                savedFilename = url.lastPathComponent
                                return true
                            } catch {
                                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                resultBar.show(
                                    ResultBarState(kind: .failure, title: "Save failed", detail: message),
                                    autoHide: false
                                )
                                return false
                            }
                        case .pin:
                            pinnedImageWindows.pin(renderedImage, near: selection)
                            return true
                        }
                    },
                    completion: { [weak self] inlineAction in
                        guard let self else { return }
                        switch inlineAction {
                        case .copy:
                            resultBar.show(
                                ResultBarState(
                                    kind: .success,
                                    title: "Annotated image copied",
                                    detail: "Can be pasted directly into WeChat or a document"
                                ),
                                autoHide: true
                            )
                            completion(.completed("Annotated image copied"))
                        case .save:
                            resultBar.show(
                                ResultBarState(
                                    kind: .success,
                                    title: "Annotated image saved",
                                    detail: savedFilename ?? "Saved to the selected location"
                                ),
                                autoHide: true
                            )
                            completion(.completed("Annotated image saved"))
                        case .pin:
                            resultBar.show(
                                ResultBarState(
                                    kind: .success,
                                    title: "Annotated image pinned",
                                    detail: "Drag to move · scroll to zoom · double-click to close"
                                ),
                                autoHide: true
                            )
                            completion(.completed("Annotated image pinned"))
                        case nil:
                            completion(.cancelled)
                        }
                    }
                )
                return
            }

            if action == .beautify {
                resultBar.show(
                    ResultBarState(
                        kind: .warning,
                        title: "Beautify entry reserved",
                        detail: "Will be wired up during the Snipaste feature-parity phase"
                    ),
                    autoHide: true
                )
                completion(.completed("Beautify entry reserved"))
                return
            }

            let selectedOCRRaw = UserDefaults.standard.string(forKey: "ocrEngine")
                ?? OCREnginePreference.appleVision.rawValue
            let selectedOCR = OCREnginePreference(rawValue: selectedOCRRaw) ?? .appleVision
            resultBar.show(
                ResultBarState(
                    kind: .processing,
                    title: selectedOCR == .deepSeekOCR2 ? "Recognizing with DeepSeek-OCR-2…" : "Recognizing text locally…",
                    detail: selectedOCR == .deepSeekOCR2 ? "The screenshot will be sent to your configured OCR service" : "The image will not be uploaded"
                ),
                autoHide: false
            )

            let languageSetting = UserDefaults.standard.string(forKey: "recognitionLanguages")
                ?? "zh-Hans,en-US"
            let languages = languageSetting
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let mergeWrappedLines = UserDefaults.standard.bool(forKey: "mergeWrappedLines")
            let result = try await ocrService.recognize(
                image: image,
                languages: languages,
                mergeWrappedLines: mergeWrappedLines
            )
            try Task.checkCancellation()

            let routeRaw = UserDefaults.standard.string(forKey: "recognitionRoute")
                ?? RecognitionRoute.localOCR.rawValue
            if routeRaw == RecognitionRoute.smart.rawValue,
               result.isLowConfidence,
               multimodalRecognitionService.isConfigured,
               confirmCloudEnhancement(confidence: result.confidence) {
                resultBar.show(
                    ResultBarState(
                        kind: .processing,
                        title: "Enhancing in the cloud…",
                        detail: "Uploaded this selection with your confirmation"
                    ),
                    autoHide: false
                )
                do {
                    let enhanced = try await multimodalRecognitionService.recognize(
                        image: image,
                        task: suggestedTask(for: result.contentType)
                    )
                    try Task.checkCancellation()
                    let committed = clipboardService.copyText(
                        enhanced,
                        initialChangeCount: initialChangeCount,
                        jobIsLatest: latestJobID == jobID
                    )
                    if committed {
                        resultBar.show(
                            ResultBarState(
                                kind: .success,
                                title: "AI-enhanced result copied",
                                detail: "Local confidence \(Int(result.confidence * 100))% · uploaded after your confirmation"
                            ),
                            autoHide: true
                        )
                        completion(.completed("AI-enhanced result copied"))
                    } else {
                        showClipboardChanged(completion: completion)
                    }
                    return
                } catch {
                    resultBar.show(
                        ResultBarState(
                            kind: .warning,
                            title: "Cloud enhancement failed, using the local result instead",
                            detail: error.localizedDescription
                        ),
                        autoHide: true
                    )
                }
            }

            guard !result.text.isEmpty else {
                let committed = clipboardService.copyImage(
                    image,
                    initialChangeCount: initialChangeCount,
                    jobIsLatest: latestJobID == jobID
                )
                if committed {
                    resultBar.show(
                        ResultBarState(kind: .warning, title: "No text found, image copied instead", detail: nil),
                        autoHide: true
                    )
                    completion(.completed("No text found, image copied instead"))
                } else {
                    showClipboardChanged(completion: completion)
                }
                return
            }

            let committed = clipboardService.copyText(
                result.text,
                initialChangeCount: initialChangeCount,
                jobIsLatest: latestJobID == jobID
            )
            guard committed else {
                showClipboardChanged(completion: completion)
                return
            }

            let kind: ResultBarKind = result.isLowConfidence ? .warning : .success
            let typeLabel = switch result.contentType {
            case .plainText: "Text"
            case .code: "Code"
            case .table: "Table"
            case .qrCode: "Link"
            case .formula: "Formula"
            case .image: "Image"
            }
            resultBar.show(
                ResultBarState(
                    kind: kind,
                    title: result.isLowConfidence ? "Copied, some text may be inaccurate" : "Copied \(typeLabel)",
                detail: "\(result.text.count) characters · \(result.engine.displayName)"
                ),
                autoHide: true
            )
            completion(.completed("Copied \(typeLabel)"))
        } catch is CancellationError {
            resultBar.hide()
            completion(.cancelled)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            resultBar.show(
                ResultBarState(kind: .failure, title: "Screenshot failed", detail: message),
                autoHide: false
            )
            completion(.failed("Screenshot failed"))
        }
    }

    private func action(for mode: CaptureMode) -> CaptureQuickAction? {
        switch mode {
        case .interactive:
            let rawValue = UserDefaults.standard.string(forKey: "postCaptureAction")
                ?? PostCaptureAction.choose.rawValue
            let preference = PostCaptureAction(rawValue: rawValue) ?? .choose
            return switch preference {
            case .choose:
                nil
            case .recognize:
                recognitionAction()
            case .translateText:
                .translateText
            case .copyImage:
                .copyImage
            case .pin:
                .pin
            case .edit:
                .edit
            case .rememberLast:
                UserDefaults.standard.string(forKey: "lastPostCaptureQuickAction")
                    .flatMap(CaptureQuickAction.init(rawValue:))
            }
        case .intelligent:
            return recognitionAction()
        case .translation:
            return .translateText
        case .image:
            return .copyImage
        case .pin:
            return .pin
        case .long:
            return nil
        }
    }

    private func performTranslation(
        image: CGImage,
        mode: ScreenshotTranslationMode,
        initialChangeCount: Int,
        jobID: UUID,
        completion: @escaping (CaptureOutcome) -> Void
    ) async throws {
        try translationService.validateConfiguration()
        let configuration = TranslationConfiguration.load()
        resultBar.show(
            ResultBarState(
                kind: .processing,
                title: "Recognizing text to translate on this device…",
                detail: "Target language: \(configuration.targetLanguage)"
            ),
            autoHide: false
        )

        let ocrResult: OCRResult
        do {
            ocrResult = try await translationOCR.recognize(
                image: image,
                languages: [],
                mergeWrappedLines: false
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            guard mode == .textOnly, configuration.usesVisionFallback else {
                throw ScreenshotTranslationServiceError.localOCRUnavailableForImage
            }
            resultBar.show(
                ResultBarState(
                    kind: .processing,
                    title: "Local recognition unavailable, switching to the vision model…",
                    detail: "Only the image from this selection is uploaded"
                ),
                autoHide: false
            )
            let translated = try await translationService.translateWithVision(image: image)
            try Task.checkCancellation()
            finishTextTranslation(
                translated,
                configuration: configuration,
                initialChangeCount: initialChangeCount,
                jobID: jobID,
                completion: completion
            )
            return
        }
        try Task.checkCancellation()

        if mode == .textOnly {
            let shouldUseVision = configuration.usesVisionFallback
                && (ocrResult.text.isEmpty || ocrResult.confidence < 0.55)
            let translated: String
            if shouldUseVision {
                resultBar.show(
                    ResultBarState(
                        kind: .processing,
                        title: "Recognizing and translating with the vision model…",
                        detail: "Only the image from this selection is uploaded"
                    ),
                    autoHide: false
                )
                translated = try await translationService.translateWithVision(image: image)
            } else {
                guard !ocrResult.text.isEmpty else { throw TranslationProviderError.emptyInput }
                resultBar.show(
                    ResultBarState(
                        kind: .processing,
                        title: "Translating text…",
                        detail: "\(configuration.sourceLanguage) → \(configuration.targetLanguage) · \(translationService.selectedTextModelName)"
                    ),
                    autoHide: false
                )
                translated = try await translationService.translateText(ocrResult.text)
            }
            try Task.checkCancellation()
            finishTextTranslation(
                translated,
                configuration: configuration,
                initialChangeCount: initialChangeCount,
                jobID: jobID,
                completion: completion
            )
            return
        }

        let lines = ocrResult.document.blocks
            .flatMap(\.lines)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { throw ScreenshotTranslationServiceError.missingTextBoxes }
        resultBar.show(
            ResultBarState(
                kind: .processing,
                title: "Batch translating \(lines.count) text regions…",
                detail: "Using \(translationService.selectedTextModelName); the original image is not sent to the text model"
            ),
            autoHide: false
        )
        let translatedLines = try await translationService.translateLines(lines)
        try Task.checkCancellation()
        let rendered = try translationRenderer.render(
            image: image,
            lines: translatedLines,
            mode: mode,
            targetLanguage: configuration.targetLanguage
        )
        let copied = clipboardService.copyImage(
            rendered,
            initialChangeCount: initialChangeCount,
            jobIsLatest: latestJobID == jobID
        )
        annotationEditor.open(image: rendered)
        let modeName = mode == .fullImage ? "full-text translated image" : "bilingual translated image"
        resultBar.show(
            ResultBarState(
                kind: .success,
                title: "Generated \(modeName)",
                detail: copied ? "Image copied, preview opened in the annotator" : "Preview opened; the clipboard changed during recognition, so it was not overwritten"
            ),
            autoHide: true
        )
        completion(.completed("Generated \(modeName)"))
    }

    private func finishTextTranslation(
        _ translated: String,
        configuration: TranslationConfiguration,
        initialChangeCount: Int,
        jobID: UUID,
        completion: @escaping (CaptureOutcome) -> Void
    ) {
        let committed = clipboardService.copyText(
            translated,
            initialChangeCount: initialChangeCount,
            jobIsLatest: latestJobID == jobID
        )
        guard committed else {
            showClipboardChanged(completion: completion)
            return
        }
        resultBar.show(
            ResultBarState(
                kind: .success,
                title: "Translation result copied",
                detail: "\(translated.count) characters · \(configuration.targetLanguage)"
            ),
            autoHide: true
        )
        completion(.completed("Translation result copied"))
    }

    private func startLongCapture(completion: @escaping (CaptureOutcome) -> Void) {
        let jobID = UUID()
        latestJobID = jobID
        let initialChangeCount = clipboardService.changeCount

        selectionOverlay.begin(
            showsActionToolbar: false
        ) { [weak self] selection, _ in
            guard let self else { return }
            guard let selection else {
                completion(.cancelled)
                return
            }

            resultBar.show(
                ResultBarState(
                    kind: .processing,
                    title: "Scrolling capture started",
                    detail: "Starting from the top of the selection, Ta will automatically lock the scroll area and capture continuously to the bottom"
                ),
                autoHide: true
            )
            scrollingCaptureSession.start(selection: selection) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .cancelled:
                    resultBar.show(
                        ResultBarState(kind: .warning, title: "Scrolling capture cancelled", detail: "Captured frames have been cleared from memory"),
                        autoHide: true
                    )
                    completion(.cancelled)
                case .failed(let message):
                    resultBar.show(
                        ResultBarState(kind: .failure, title: "Scrolling capture failed", detail: message),
                        autoHide: false
                    )
                    completion(.failed("Scrolling capture failed"))
                case .completed(let images, let acceptedFrames, let skippedFrames, let reviewedSeams):
                    guard let firstImage = images.first else {
                        completion(.failed("Scrolling capture did not produce an image"))
                        return
                    }
                    let copied = clipboardService.copyImage(
                        firstImage,
                        initialChangeCount: initialChangeCount,
                        jobIsLatest: latestJobID == jobID
                    )
                    do {
                        let urls = try imageExportService.save(
                            images,
                            suggestedBaseName: "AI-Long-Screenshot.png"
                        )
                        let status = urls == nil ? "Scrolling capture generated" : "Scrolling capture saved"
                        let totalHeight = images.reduce(0) { $0 + $1.height }
                        var details = "\(firstImage.width) × \(totalHeight) · \(acceptedFrames) valid frames"
                        if skippedFrames > 0 {
                            details += " · skipped \(skippedFrames) frames"
                        }
                        if reviewedSeams > 0 {
                            details += " · \(reviewedSeams) low-confidence seams"
                        }
                        if images.count > 1 {
                            details += " · split into \(images.count) segments"
                        }
                        details += copied
                            ? (images.count > 1 ? " · copied segment 1" : " · copied")
                            : " · did not overwrite the changed clipboard"
                        resultBar.show(
                            ResultBarState(kind: .success, title: status, detail: details),
                            autoHide: true
                        )
                        completion(.completed(status))
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        resultBar.show(
                            ResultBarState(
                                kind: .warning,
                                title: copied ? "Scrolling capture copied, but saving failed" : "Scrolling capture failed to save",
                                detail: message
                            ),
                            autoHide: false
                        )
                        completion(copied ? .completed("Scrolling capture copied") : .failed("Scrolling capture failed to save"))
                    }
                }
            }
        }
    }

    private func recognitionAction() -> CaptureQuickAction {
        let rawValue = UserDefaults.standard.string(forKey: "recognitionRoute")
            ?? RecognitionRoute.localOCR.rawValue
        switch RecognitionRoute(rawValue: rawValue) ?? .localOCR {
        case .localOCR, .smart:
            return .localOCR
        case .multimodal:
            return .multimodal
        }
    }

    private func confirmCloudEnhancement(confidence: Float) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Local OCR confidence is low (\(Int(confidence * 100))%)"
        alert.informativeText = "Upload this selection to the configured vision model for enhancement? It won't be uploaded unless you confirm."
        alert.addButton(withTitle: "Upload & Enhance")
        alert.addButton(withTitle: "Use Local Result")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func suggestedTask(for contentType: CaptureContentType) -> MultimodalTaskTemplate {
        switch contentType {
        case .code: .explainCode
        case .table: .tableMarkdown
        case .formula: .formulaLaTeX
        case .plainText, .qrCode, .image: .extractText
        }
    }

    private func showClipboardChanged(completion: @escaping (CaptureOutcome) -> Void) {
        resultBar.show(
            ResultBarState(
                kind: .warning,
                title: "Result is ready, but the clipboard was not overwritten",
                detail: "You copied something else during recognition"
            ),
            autoHide: false
        )
        completion(.completed("Clipboard changed, not overwritten"))
    }

    private func ensureScreenCapturePermission(
        completion: @escaping (CaptureOutcome) -> Void
    ) -> Bool {
        if ScreenCapturePermissionService.isGranted {
            return true
        }

        let granted = ScreenCapturePermissionService.request()
        guard granted else {
            resultBar.show(
                ResultBarState(
                    kind: .failure,
                    title: "Screen Recording permission is required",
                    detail: "Please allow \"\(TaBrand.name)\" in System Settings, then try again"
                ),
                autoHide: false
            )
            completion(.failed("Screen Recording permission is required"))
            return false
        }
        return true
    }
}
