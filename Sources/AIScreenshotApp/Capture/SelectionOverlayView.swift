import AppKit
import AIScreenshotCore

final class SelectionOverlayView: NSView {
    var onFinish: ((CGRect?, CaptureQuickAction?) -> Void)?
    var showsActionToolbar = false

    private var dragStart: CGPoint?
    private var selectionRect: CGRect?
    private var actionToolbar: NSVisualEffectView?
    private var showsPresetFixture = false

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    func showPresetSelection(_ rect: CGRect) {
        guard rect.width >= 4, rect.height >= 4 else { return }
        showsPresetFixture = true
        selectionRect = rect.integral
        dragStart = nil
        needsDisplay = true
        if showsActionToolbar {
            showActionToolbar(for: rect.integral)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if showsActionToolbar,
           event.clickCount == 2,
           let selectionRect,
           selectionRect.contains(convert(event.locationInWindow, from: nil)) {
            onFinish?(selectionRect, .copyImage)
            return
        }

        removeActionToolbar()
        dragStart = convert(event.locationInWindow, from: nil)
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = normalizedRect(from: dragStart, to: current).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else {
            onFinish?(nil, nil)
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        let rect = normalizedRect(from: dragStart, to: current).intersection(bounds)
        if rect.width >= 4, rect.height >= 4 {
            selectionRect = rect.integral
            self.dragStart = nil
            needsDisplay = true
            if showsActionToolbar {
                showActionToolbar(for: rect.integral)
            } else {
                onFinish?(rect.integral, nil)
            }
        } else {
            onFinish?(nil, nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        removeActionToolbar()
        dragStart = nil
        selectionRect = nil
        needsDisplay = true
        onFinish?(nil, nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil, nil)
        } else if showsActionToolbar,
                  (event.keyCode == 36 || event.keyCode == 76),
                  let selectionRect {
            onFinish?(selectionRect, .copyImage)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        context.fill(bounds)

        guard let selectionRect else {
            drawHint("拖动选择区域 · 右键 / Esc 取消", at: CGPoint(x: bounds.midX, y: bounds.midY))
            return
        }

        if showsPresetFixture {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(selectionRect)
            drawPresetFixture(in: selectionRect)
        } else {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.restoreGState()
        }

        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(2)
        context.stroke(selectionRect.insetBy(dx: 1, dy: 1))

        let dimensions = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        drawHint(dimensions, at: CGPoint(x: selectionRect.midX, y: max(26, selectionRect.minY - 18)))
    }

    private func showActionToolbar(for selectionRect: CGRect) {
        removeActionToolbar()

        let actions: [(CaptureQuickAction, String, String)] = [
            (.localOCR, "取字", "text.viewfinder"),
            (.multimodal, "AI 识图", "sparkles"),
            (.translate, "翻译", "character.book.closed"),
            (.copyImage, "复制", "doc.on.doc"),
            (.pin, "钉图", "pin.fill"),
            (.edit, "标注", "pencil.tip.crop.circle"),
            (.beautify, "美化", "wand.and.stars"),
            (.save, "保存", "square.and.arrow.down")
        ]

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)

        for (index, item) in actions.enumerated() {
            let button = NSButton(title: item.1, target: self, action: #selector(handleAction(_:)))
            button.tag = CaptureQuickAction.allCases.firstIndex(of: item.0) ?? index
            button.bezelStyle = .recessed
            button.controlSize = .small
            button.image = NSImage(systemSymbolName: item.2, accessibilityDescription: item.1)
            button.imagePosition = .imageLeading
            button.toolTip = item.1
            stack.addArrangedSubview(button)
        }

        let toolbar = NSVisualEffectView()
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 11
        toolbar.layer?.masksToBounds = true
        toolbar.addSubview(stack)

        let fittingSize = stack.fittingSize
        let toolbarSize = CGSize(width: fittingSize.width, height: max(42, fittingSize.height))
        let proposedBelow = selectionRect.minY - toolbarSize.height - 10
        let y = proposedBelow >= 8
            ? proposedBelow
            : min(bounds.height - toolbarSize.height - 8, selectionRect.maxY + 10)
        let x = min(
            max(8, selectionRect.maxX - toolbarSize.width),
            bounds.width - toolbarSize.width - 8
        )
        toolbar.frame = CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
        stack.frame = toolbar.bounds
        addSubview(toolbar)
        actionToolbar = toolbar
    }

    @objc
    private func handleAction(_ sender: NSButton) {
        guard let selectionRect,
              CaptureQuickAction.allCases.indices.contains(sender.tag) else {
            return
        }
        onFinish?(selectionRect, CaptureQuickAction.allCases[sender.tag])
    }

    private func removeActionToolbar() {
        actionToolbar?.removeFromSuperview()
        actionToolbar = nil
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func drawHint(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawPresetFixture(in rect: CGRect) {
        let title = "Ta · 一次截图，多种下一步"
        title.draw(at: CGPoint(x: rect.minX + 42, y: rect.maxY - 82), withAttributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ])
        "取字 · AI 识图 · 翻译 · 钉图 · 标注 · 美化".draw(
            at: CGPoint(x: rect.minX + 42, y: rect.maxY - 130),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSColor(calibratedRed: 0.91, green: 0.25, blue: 0.18, alpha: 0.10).setFill()
        NSBezierPath(
            roundedRect: CGRect(
                x: rect.minX + 42,
                y: rect.minY + 48,
                width: rect.width - 84,
                height: max(58, rect.height - 220)
            ),
            xRadius: 18,
            yRadius: 18
        ).fill()
    }
}
