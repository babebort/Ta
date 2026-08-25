import AppKit

enum InlineAnnotationAction {
    case copy
    case save
    case pin
}

enum InlineAnnotationToolbarMetrics {
    static let buttonSize = CGSize(width: 32, height: 30)
    static let symbolPointSize: CGFloat = 10
    static let textPointSize: CGFloat = 12
    static let spacing: CGFloat = 3
}

struct InlineAnnotationLayout {
    static func toolbarFrame(
        selection: CGRect,
        screenBounds: CGRect,
        toolbarSize: CGSize,
        gap: CGFloat = 10,
        margin: CGFloat = 8
    ) -> CGRect {
        let availableWidth = max(1, screenBounds.width - margin * 2)
        let width = min(toolbarSize.width, availableWidth)
        let desiredX = selection.midX - width / 2
        let x = min(max(desiredX, screenBounds.minX + margin), screenBounds.maxX - width - margin)
        let belowY = selection.minY - toolbarSize.height - gap
        let y: CGFloat
        if belowY >= screenBounds.minY + margin {
            y = belowY
        } else {
            y = min(selection.maxY + gap, screenBounds.maxY - toolbarSize.height - margin)
        }
        return CGRect(x: x, y: y, width: width, height: toolbarSize.height)
    }
}

@MainActor
final class InlineAnnotationController: NSObject {
    typealias ActionHandler = (InlineAnnotationAction, CGImage) -> Bool

    private var panel: InlineAnnotationPanel?
    private var canvas: AnnotationCanvasView?
    private var actionHandler: ActionHandler?
    private var completion: ((InlineAnnotationAction?) -> Void)?
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private weak var colorWell: NSColorWell?
    private weak var widthSlider: NSSlider?
    private weak var textSizePopUp: NSPopUpButton?

    func open(
        image: CGImage,
        selection: CaptureSelection,
        actionHandler: @escaping ActionHandler,
        completion: @escaping (InlineAnnotationAction?) -> Void
    ) {
        closePanel()
        self.actionHandler = actionHandler
        self.completion = completion

        let panel = InlineAnnotationPanel(
            contentRect: selection.screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.onCancel = { [weak self] in self?.finish(nil) }
        panel.onCommit = { [weak self] in self?.perform(.copy) }

        let screenBounds = CGRect(origin: .zero, size: selection.screenFrame.size)
        let selectionFrame = CGRect(
            x: selection.globalRect.minX - selection.screenFrame.minX,
            y: selection.globalRect.minY - selection.screenFrame.minY,
            width: selection.globalRect.width,
            height: selection.globalRect.height
        ).intersection(screenBounds)

        let root = InlineAnnotationOverlayView(frame: screenBounds)
        root.onCancel = { [weak self] in self?.finish(nil) }

        let canvas = AnnotationCanvasView(image: image, contentInset: 0)
        canvas.frame = selectionFrame
        canvas.wantsLayer = true
        canvas.layer?.borderColor = NSColor.controlAccentColor.cgColor
        canvas.layer?.borderWidth = 2
        canvas.onCancel = { [weak self] in self?.finish(nil) }
        canvas.onCommit = { [weak self] in self?.perform(.copy) }
        root.addSubview(canvas)

        let toolbar = makeToolbar(canvas: canvas)
        root.addSubview(toolbar)
        let naturalSize = toolbar.subviews.first?.fittingSize ?? CGSize(width: 720, height: 42)
        let toolbarSize = CGSize(width: naturalSize.width, height: max(42, naturalSize.height))
        toolbar.frame = InlineAnnotationLayout.toolbarFrame(
            selection: selectionFrame,
            screenBounds: screenBounds,
            toolbarSize: toolbarSize
        )
        toolbar.subviews.first?.frame = toolbar.bounds

        panel.contentView = root
        self.panel = panel
        self.canvas = canvas

        // Match Snipaste: edit over the captured Space without activating Ta
        // and switching the user back to the Space that owns Ta's main window.
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(canvas)
    }

    private func makeToolbar(canvas: AnnotationCanvasView) -> NSVisualEffectView {
        toolButtons.removeAll()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = InlineAnnotationToolbarMetrics.spacing
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        let tools: [(AnnotationTool, String?)] = [
            (.crop, "crop"),
            (.rectangle, "rectangle"),
            (.ellipse, "circle"),
            (.arrow, "arrow.up.right"),
            (.pen, "pencil.tip"),
            (.highlighter, "highlighter"),
            (.text, nil),
            (.number, "1.circle"),
            (.mosaic, "square.grid.3x3.fill"),
            (.mosaicBrush, "paintbrush.pointed.fill"),
            (.blur, "drop.degreesign"),
            (.eraser, "eraser"),
            (.magnify, "plus.magnifyingglass")
        ]
        for (tool, symbol) in tools {
            let tooltip = switch tool {
            case .mosaic: "框选马赛克：拖出矩形区域"
            case .mosaicBrush: "涂抹马赛克：像画笔一样按住并连续涂抹"
            default: tool.displayName
            }
            let button = symbol.map {
                iconButton(symbol: $0, tooltip: tooltip, action: #selector(selectTool(_:)))
            } ?? textButton(title: "T", tooltip: "文字：点击截图后输入", action: #selector(selectTool(_:)))
            button.tag = tool.rawValue
            button.setButtonType(.toggle)
            button.state = tool == .rectangle ? .on : .off
            stack.addArrangedSubview(button)
            toolButtons[tool] = button
        }
        updateToolButtonAppearance(selected: .rectangle)

        stack.addArrangedSubview(separator())

        let color = NSColorWell()
        color.color = .systemRed
        color.target = canvas
        color.action = #selector(AnnotationCanvasView.changeColor(_:))
        color.toolTip = "颜色"
        color.widthAnchor.constraint(equalToConstant: 32).isActive = true
        color.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.addArrangedSubview(color)
        colorWell = color

        let parameterControl = NSView()
        parameterControl.widthAnchor.constraint(equalToConstant: 72).isActive = true
        parameterControl.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let width = NSSlider(value: 5, minValue: 1, maxValue: 22, target: canvas, action: #selector(AnnotationCanvasView.changeWidth(_:)))
        width.toolTip = "粗细（滚轮或 [ ] 调整）"
        width.translatesAutoresizingMaskIntoConstraints = false
        parameterControl.addSubview(width)

        let textSize = NSPopUpButton()
        for size in AnnotationTextMetrics.availableSizes {
            textSize.addItem(withTitle: String(Int(size)))
            textSize.lastItem?.tag = Int(size)
        }
        textSize.selectItem(withTag: Int(AnnotationTextMetrics.defaultSize))
        textSize.target = canvas
        textSize.action = #selector(AnnotationCanvasView.changeTextSize(_:))
        textSize.toolTip = "字号（编辑时滚轮可调）"
        textSize.isHidden = true
        textSize.translatesAutoresizingMaskIntoConstraints = false
        parameterControl.addSubview(textSize)

        NSLayoutConstraint.activate([
            width.leadingAnchor.constraint(equalTo: parameterControl.leadingAnchor),
            width.trailingAnchor.constraint(equalTo: parameterControl.trailingAnchor),
            width.centerYAnchor.constraint(equalTo: parameterControl.centerYAnchor),
            textSize.leadingAnchor.constraint(equalTo: parameterControl.leadingAnchor),
            textSize.trailingAnchor.constraint(equalTo: parameterControl.trailingAnchor),
            textSize.centerYAnchor.constraint(equalTo: parameterControl.centerYAnchor)
        ])
        stack.addArrangedSubview(parameterControl)
        widthSlider = width
        textSizePopUp = textSize
        canvas.onWidthChanged = { [weak width] value in width?.doubleValue = Double(value) }
        canvas.onTextSizeChanged = { [weak textSize] value in textSize?.selectItem(withTag: Int(value)) }

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(iconButton(symbol: "arrow.uturn.backward", tooltip: "撤销 ⌘Z", target: canvas, action: #selector(AnnotationCanvasView.undo)))
        stack.addArrangedSubview(iconButton(symbol: "arrow.uturn.forward", tooltip: "重做 ⇧⌘Z", target: canvas, action: #selector(AnnotationCanvasView.redo)))

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(iconButton(symbol: "doc.on.doc", tooltip: "复制并结束", action: #selector(copyAndFinish)))
        stack.addArrangedSubview(iconButton(symbol: "square.and.arrow.down", tooltip: "保存", action: #selector(saveAndFinish)))
        stack.addArrangedSubview(iconButton(symbol: "pin.fill", tooltip: "钉在屏幕上", action: #selector(pinAndFinish)))
        stack.addArrangedSubview(iconButton(symbol: "xmark", tooltip: "取消 Esc", action: #selector(cancel)))

        let done = NSButton(title: "完成", target: self, action: #selector(copyAndFinish))
        done.bezelStyle = .rounded
        done.controlSize = .small
        done.keyEquivalent = "\r"
        done.toolTip = "完成并复制"
        stack.addArrangedSubview(done)

        let toolbar = NSVisualEffectView()
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 10
        toolbar.layer?.masksToBounds = true
        toolbar.addSubview(stack)
        return toolbar
    }

    private func iconButton(
        symbol: String,
        tooltip: String,
        target: AnyObject? = nil,
        action: Selector
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()
        let configured = image.withSymbolConfiguration(.init(pointSize: InlineAnnotationToolbarMetrics.symbolPointSize, weight: .medium)) ?? image
        let button = NSButton(image: configured, target: target ?? self, action: action)
        button.bezelStyle = .recessed
        button.controlSize = .regular
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.widthAnchor.constraint(equalToConstant: InlineAnnotationToolbarMetrics.buttonSize.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: InlineAnnotationToolbarMetrics.buttonSize.height).isActive = true
        return button
    }

    private func textButton(title: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .recessed
        button.controlSize = .regular
        button.font = .systemFont(ofSize: InlineAnnotationToolbarMetrics.textPointSize, weight: .semibold)
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.widthAnchor.constraint(equalToConstant: InlineAnnotationToolbarMetrics.buttonSize.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: InlineAnnotationToolbarMetrics.buttonSize.height).isActive = true
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return box
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard let tool = AnnotationTool(rawValue: sender.tag), let canvas else { return }
        canvas.setTool(tool)
        for (candidate, button) in toolButtons {
            button.state = candidate == tool ? .on : .off
        }
        updateToolButtonAppearance(selected: tool)
        widthSlider?.isHidden = tool == .text
        textSizePopUp?.isHidden = tool != .text
        panel?.makeFirstResponder(canvas)
    }

    private func updateToolButtonAppearance(selected tool: AnnotationTool) {
        for (candidate, button) in toolButtons {
            button.contentTintColor = candidate == tool ? .controlAccentColor : .labelColor
        }
    }

    @objc private func copyAndFinish() { perform(.copy) }
    @objc private func saveAndFinish() { perform(.save) }
    @objc private func pinAndFinish() { perform(.pin) }
    @objc private func cancel() { finish(nil) }

    private func perform(_ action: InlineAnnotationAction) {
        guard let panel, let canvas, let actionHandler else { return }
        if action == .save { panel.orderOut(nil) }
        if actionHandler(action, canvas.renderedImage()) {
            finish(action)
        } else if action == .save {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(canvas)
        }
    }

    private func finish(_ action: InlineAnnotationAction?) {
        let completion = self.completion
        self.completion = nil
        actionHandler = nil
        closePanel()
        completion?(action)
    }

    private func closePanel() {
        colorWell?.deactivate()
        NSColorPanel.shared.orderOut(nil)
        colorWell = nil
        widthSlider = nil
        textSizePopUp = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        canvas = nil
        toolButtons.removeAll()
        // The non-activating panel leaves the source application in front for
        // the whole edit session, so explicitly activating it here would cause
        // an unnecessary Space jump after copy/save/pin.
    }
}

private final class InlineAnnotationOverlayView: NSView {
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }
}

private final class InlineAnnotationPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else if [36, 76].contains(event.keyCode) {
            onCommit?()
        } else {
            super.keyDown(with: event)
        }
    }
}
