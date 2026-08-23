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
        "Tuo UI Smoke Test".draw(at: CGPoint(x: 60, y: 470), withAttributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: NSColor.black
        ])
        "裁剪 · 编号 · 高亮 · 选择编辑 · 局部放大".draw(at: CGPoint(x: 60, y: 390), withAttributes: [
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

        selectionOverlay.begin(showsActionToolbar: configuredAction == nil) { [weak self] selection, selectedAction in
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
            completion(.failed("找不到显示器"))
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
                        ResultBarState(kind: .success, title: "已复制图片", detail: "\(image.width) × \(image.height)"),
                        autoHide: true
                    )
                    completion(.completed("已复制图片"))
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
                        title: "已钉在屏幕上",
                        detail: "拖动移动 · 滚轮缩放 · ⌘滚轮调透明度 · 双击关闭"
                    ),
                    autoHide: true
                )
                completion(.completed("已钉图"))
                return
            }

            if action == .multimodal {
                resultBar.show(
                    ResultBarState(
                        kind: .processing,
                        title: "正在调用多模态模型…",
                        detail: "仅上传本次主动框选的图片"
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
                                title: "AI 识图结果已复制",
                                detail: "\(text.count) 个字符 · \(UserDefaults.standard.string(forKey: "providerVisionModel") ?? "视觉模型")"
                            ),
                            autoHide: true
                        )
                        completion(.completed("AI 识图结果已复制"))
                    } else {
                        showClipboardChanged(completion: completion)
                    }
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    resultBar.show(
                        ResultBarState(kind: .failure, title: "AI 识图失败", detail: message),
                        autoHide: false
                    )
                    completion(.failed("AI 识图失败"))
                }
                return
            }

            if action == .translate || action == .translateText {
                let mode: ScreenshotTranslationMode?
                if action == .translateText {
                    mode = .textOnly
                } else {
                    mode = chooseTranslationMode()
                }
                guard let mode else {
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
                        ResultBarState(kind: .failure, title: "截图翻译失败", detail: message),
                        autoHide: false
                    )
                    completion(.failed("截图翻译失败"))
                }
                return
            }

            if action == .save {
                do {
                    if let url = try imageExportService.save(image) {
                        resultBar.show(
                            ResultBarState(
                                kind: .success,
                                title: "截图已保存",
                                detail: url.lastPathComponent
                            ),
                            autoHide: true
                        )
                        completion(.completed("截图已保存"))
                    } else {
                        completion(.cancelled)
                    }
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    resultBar.show(
                        ResultBarState(kind: .failure, title: "保存失败", detail: message),
                        autoHide: false
                    )
                    completion(.failed("保存失败"))
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
                                    ResultBarState(kind: .failure, title: "保存失败", detail: message),
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
                                    title: "标注图片已复制",
                                    detail: "可直接粘贴到微信或文档"
                                ),
                                autoHide: true
                            )
                            completion(.completed("标注图片已复制"))
                        case .save:
                            resultBar.show(
                                ResultBarState(
                                    kind: .success,
                                    title: "标注图片已保存",
                                    detail: savedFilename ?? "已保存到所选位置"
                                ),
                                autoHide: true
                            )
                            completion(.completed("标注图片已保存"))
                        case .pin:
                            resultBar.show(
                                ResultBarState(
                                    kind: .success,
                                    title: "标注图片已钉住",
                                    detail: "拖动移动 · 滚轮缩放 · 双击关闭"
                                ),
                                autoHide: true
                            )
                            completion(.completed("标注图片已钉住"))
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
                        title: "美化入口已预留",
                        detail: "将在 Snipaste 功能对标阶段接入"
                    ),
                    autoHide: true
                )
                completion(.completed("美化入口已预留"))
                return
            }

            let selectedOCRRaw = UserDefaults.standard.string(forKey: "ocrEngine")
                ?? OCREnginePreference.appleVision.rawValue
            let selectedOCR = OCREnginePreference(rawValue: selectedOCRRaw) ?? .appleVision
            resultBar.show(
                ResultBarState(
                    kind: .processing,
                    title: selectedOCR == .deepSeekOCR2 ? "正在使用 DeepSeek-OCR-2 识别…" : "正在本地识别文字…",
                    detail: selectedOCR == .deepSeekOCR2 ? "截图将发送到你配置的 OCR 服务" : "图片不会上传"
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
                        title: "正在进行云端增强…",
                        detail: "已按你的确认上传本次选区"
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
                                title: "AI 增强结果已复制",
                                detail: "本地置信度 \(Int(result.confidence * 100))% · 已经你确认后上传"
                            ),
                            autoHide: true
                        )
                        completion(.completed("AI 增强结果已复制"))
                    } else {
                        showClipboardChanged(completion: completion)
                    }
                    return
                } catch {
                    resultBar.show(
                        ResultBarState(
                            kind: .warning,
                            title: "云端增强失败，继续使用本地结果",
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
                        ResultBarState(kind: .warning, title: "未发现文字，已复制图片", detail: nil),
                        autoHide: true
                    )
                    completion(.completed("未发现文字，已复制图片"))
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
            case .plainText: "文本"
            case .code: "代码"
            case .table: "表格"
            case .qrCode: "链接"
            case .formula: "公式"
            case .image: "图片"
            }
            resultBar.show(
                ResultBarState(
                    kind: kind,
                    title: result.isLowConfidence ? "已复制，部分文字可能有误" : "已复制\(typeLabel)",
                detail: "\(result.text.count) 个字符 · \(result.engine.displayName)"
                ),
                autoHide: true
            )
            completion(.completed("已复制\(typeLabel)"))
        } catch is CancellationError {
            resultBar.hide()
            completion(.cancelled)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            resultBar.show(
                ResultBarState(kind: .failure, title: "截图失败", detail: message),
                autoHide: false
            )
            completion(.failed("截图失败"))
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
        guard translationService.isConfigured else {
            throw TranslationProviderError.missingAPIKey
        }
        let configuration = TranslationConfiguration.load()
        resultBar.show(
            ResultBarState(
                kind: .processing,
                title: "正在本机识别待翻译文字…",
                detail: "目标语言：\(configuration.targetLanguage)"
            ),
            autoHide: false
        )

        let ocrResult = try await translationOCR.recognize(
            image: image,
            languages: [],
            mergeWrappedLines: false
        )
        try Task.checkCancellation()

        if mode == .textOnly {
            let shouldUseVision = configuration.usesVisionFallback
                && (ocrResult.text.isEmpty || ocrResult.confidence < 0.55)
            let translated: String
            if shouldUseVision {
                resultBar.show(
                    ResultBarState(
                        kind: .processing,
                        title: "正在使用视觉模型识别并翻译…",
                        detail: "仅上传本次主动框选的图片"
                    ),
                    autoHide: false
                )
                translated = try await translationService.translateWithVision(image: image)
            } else {
                guard !ocrResult.text.isEmpty else { throw TranslationProviderError.emptyInput }
                resultBar.show(
                    ResultBarState(
                        kind: .processing,
                        title: "正在翻译文字…",
                        detail: "\(configuration.sourceLanguage) → \(configuration.targetLanguage) · \(configuration.textModel)"
                    ),
                    autoHide: false
                )
                translated = try await translationService.translateText(ocrResult.text)
            }
            try Task.checkCancellation()
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
                    title: "翻译结果已复制",
                    detail: "\(translated.count) 个字符 · \(configuration.targetLanguage)"
                ),
                autoHide: true
            )
            completion(.completed("翻译结果已复制"))
            return
        }

        let lines = ocrResult.document.blocks
            .flatMap(\.lines)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { throw ScreenshotTranslationServiceError.missingTextBoxes }
        resultBar.show(
            ResultBarState(
                kind: .processing,
                title: "正在批量翻译 \(lines.count) 个文字区域…",
                detail: "使用 \(configuration.textModel)，原图不会发送给文字模型"
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
        let modeName = mode == .fullImage ? "全文翻译图片" : "双语翻译图片"
        resultBar.show(
            ResultBarState(
                kind: .success,
                title: "已生成\(modeName)",
                detail: copied ? "已复制图片，并在标注器中打开预览" : "已打开预览；识别期间剪贴板有变化，未自动覆盖"
            ),
            autoHide: true
        )
        completion(.completed("已生成\(modeName)"))
    }

    private func chooseTranslationMode() -> ScreenshotTranslationMode? {
        let configuration = TranslationConfiguration.load()
        let modes = ScreenshotTranslationMode.allCases
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28), pullsDown: false)
        modes.forEach { picker.addItem(withTitle: $0.displayName) }
        if let index = modes.firstIndex(of: configuration.defaultMode) {
            picker.selectItem(at: index)
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "选择截图翻译方式"
        alert.informativeText = "文字模式会复制译文；图片模式会生成可继续标注、复制和保存的新图片。"
        alert.accessoryView = picker
        alert.addButton(withTitle: "开始翻译")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn,
              modes.indices.contains(picker.indexOfSelectedItem) else {
            return nil
        }
        return modes[picker.indexOfSelectedItem]
    }

    private func startLongCapture(completion: @escaping (CaptureOutcome) -> Void) {
        let jobID = UUID()
        latestJobID = jobID
        let initialChangeCount = clipboardService.changeCount

        selectionOverlay.begin(showsActionToolbar: false) { [weak self] selection, _ in
            guard let self else { return }
            guard let selection else {
                completion(.cancelled)
                return
            }

            resultBar.show(
                ResultBarState(
                    kind: .processing,
                    title: "长截图已开始",
                    detail: "可手动上下滚动或按需自动滚动，完成后检查接缝"
                ),
                autoHide: true
            )
            scrollingCaptureSession.start(selection: selection) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .cancelled:
                    resultBar.show(
                        ResultBarState(kind: .warning, title: "已取消长截图", detail: "采集帧已从内存清除"),
                        autoHide: true
                    )
                    completion(.cancelled)
                case .failed(let message):
                    resultBar.show(
                        ResultBarState(kind: .failure, title: "长截图失败", detail: message),
                        autoHide: false
                    )
                    completion(.failed("长截图失败"))
                case .completed(let images, let acceptedFrames, let skippedFrames, let reviewedSeams):
                    guard let firstImage = images.first else {
                        completion(.failed("长截图没有生成图片"))
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
                        let status = urls == nil ? "长截图已生成" : "长截图已保存"
                        let totalHeight = images.reduce(0) { $0 + $1.height }
                        var details = "\(firstImage.width) × \(totalHeight) · \(acceptedFrames) 个有效画面"
                        if skippedFrames > 0 {
                            details += " · 跳过 \(skippedFrames) 帧"
                        }
                        if reviewedSeams > 0 {
                            details += " · \(reviewedSeams) 个低置信度接缝"
                        }
                        if images.count > 1 {
                            details += " · 已分为 \(images.count) 段"
                        }
                        details += copied
                            ? (images.count > 1 ? " · 已复制第 1 段" : " · 已复制")
                            : " · 未覆盖已变化的剪贴板"
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
                                title: copied ? "长截图已复制，但保存失败" : "长截图保存失败",
                                detail: message
                            ),
                            autoHide: false
                        )
                        completion(copied ? .completed("长截图已复制") : .failed("长截图保存失败"))
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
        alert.messageText = "本地 OCR 置信度较低（\(Int(confidence * 100))%）"
        alert.informativeText = "是否把本次主动框选的图片上传到已配置的视觉模型进行增强？不确认就不会上传。"
        alert.addButton(withTitle: "上传并增强")
        alert.addButton(withTitle: "使用本地结果")
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
                title: "结果已就绪，但没有覆盖剪贴板",
                detail: "识别期间你复制了其他内容"
            ),
            autoHide: false
        )
        completion(.completed("剪贴板已变化，未覆盖"))
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
                    title: "需要屏幕录制权限",
                    detail: "请在系统设置中允许「\(TaBrand.name)」后重试"
                ),
                autoHide: false
            )
            completion(.failed("需要屏幕录制权限"))
            return false
        }
        return true
    }
}
