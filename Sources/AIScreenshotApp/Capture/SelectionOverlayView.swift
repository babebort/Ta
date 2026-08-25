import AppKit
import AIScreenshotCore

enum CaptureActionToolbarLayout {
    static let actions: [(action: CaptureQuickAction, title: String, symbol: String)] = [
        (.beautify, "美化", "wand.and.stars"),
        (.multimodal, "AI 识图", "sparkles"),
        (.localOCR, "取字", "text.viewfinder"),
        (.translate, "翻译", "character.book.closed"),
        (.edit, "标注", "pencil.tip.crop.circle"),
        (.pin, "钉图", "pin.fill"),
        (.copyImage, "复制", "doc.on.doc"),
        (.save, "保存", "square.and.arrow.down")
    ]
}

enum SelectionResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

enum SelectionDragMode {
    case creating
    case moving(original: CGRect)
    case resizing(handle: SelectionResizeHandle, original: CGRect)
}

enum SelectionRectEditor {
    static func moved(_ rect: CGRect, by offset: CGPoint, inside bounds: CGRect) -> CGRect {
        let x = min(max(bounds.minX, rect.minX + offset.x), bounds.maxX - rect.width)
        let y = min(max(bounds.minY, rect.minY + offset.y), bounds.maxY - rect.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size).integral
    }

    static func resized(
        _ rect: CGRect,
        handle: SelectionResizeHandle,
        to point: CGPoint,
        inside bounds: CGRect
    ) -> CGRect {
        let point = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
        let x1: CGFloat
        let x2: CGFloat
        let y1: CGFloat
        let y2: CGFloat
        switch handle {
        case .topLeft:
            (x1, x2, y1, y2) = (point.x, rect.maxX, rect.minY, point.y)
        case .top:
            (x1, x2, y1, y2) = (rect.minX, rect.maxX, rect.minY, point.y)
        case .topRight:
            (x1, x2, y1, y2) = (rect.minX, point.x, rect.minY, point.y)
        case .right:
            (x1, x2, y1, y2) = (rect.minX, point.x, rect.minY, rect.maxY)
        case .bottomRight:
            (x1, x2, y1, y2) = (rect.minX, point.x, point.y, rect.maxY)
        case .bottom:
            (x1, x2, y1, y2) = (rect.minX, rect.maxX, point.y, rect.maxY)
        case .bottomLeft:
            (x1, x2, y1, y2) = (point.x, rect.maxX, point.y, rect.maxY)
        case .left:
            (x1, x2, y1, y2) = (point.x, rect.maxX, rect.minY, rect.maxY)
        }
        return CGRect(
            x: min(x1, x2),
            y: min(y1, y2),
            width: abs(x2 - x1),
            height: abs(y2 - y1)
        ).intersection(bounds).integral
    }
}

final class SelectionOverlayView: NSView {
    var onFinish: ((CGRect?, CaptureQuickAction?) -> Void)?
    var showsActionToolbar = false

    private var dragStart: CGPoint?
    private var dragMode: SelectionDragMode = .creating
    private var selectionRect: CGRect?
    private var pendingSnapRect: CGRect?
    private var hoveredSnapTarget: WindowSnapTarget?
    private var snapTargets: [WindowSnapTarget] = []
    private var didDrag = false
    private var isTransitioning = false
    private var actionToolbar: NSVisualEffectView?
    private var showsPresetFixture = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func configureSnapTargets(_ targets: [WindowSnapTarget]) {
        snapTargets = targets
        updateHoveredSnapTarget(at: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
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
        guard !isTransitioning else { return }
        if showsActionToolbar,
           event.clickCount == 2,
           let selectionRect,
           selectionRect.contains(convert(event.locationInWindow, from: nil)) {
            onFinish?(selectionRect, .copyImage)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        removeActionToolbar()
        dragStart = point
        if showsActionToolbar, let selectionRect,
           let handle = resizeHandle(at: point, for: selectionRect) {
            dragMode = .resizing(handle: handle, original: selectionRect)
            pendingSnapRect = nil
        } else if showsActionToolbar, let selectionRect, selectionRect.contains(point) {
            dragMode = .moving(original: selectionRect)
            pendingSnapRect = nil
        } else {
            dragMode = .creating
            pendingSnapRect = hoveredSnapTarget?.frame
            selectionRect = pendingSnapRect
        }
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard didDrag || hypot(current.x - dragStart.x, current.y - dragStart.y) >= 3 else { return }
        didDrag = true
        switch dragMode {
        case .creating:
            pendingSnapRect = nil
            hoveredSnapTarget = nil
            selectionRect = normalizedRect(from: dragStart, to: current).intersection(bounds)
        case .moving(let original):
            selectionRect = SelectionRectEditor.moved(
                original,
                by: CGPoint(x: current.x - dragStart.x, y: current.y - dragStart.y),
                inside: bounds
            )
        case .resizing(let handle, let original):
            selectionRect = SelectionRectEditor.resized(
                original,
                handle: handle,
                to: current,
                inside: bounds
            )
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else {
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        let rect: CGRect
        switch dragMode {
        case .creating:
            rect = pendingSnapRect ?? normalizedRect(from: dragStart, to: current).intersection(bounds)
        case .moving(let original):
            rect = didDrag ? (selectionRect ?? original) : original
        case .resizing(_, let original):
            rect = didDrag ? (selectionRect ?? original) : original
        }
        if rect.width >= 4, rect.height >= 4 {
            selectionRect = rect.integral
            self.dragStart = nil
            pendingSnapRect = nil
            dragMode = .creating
            didDrag = false
            needsDisplay = true
            if showsActionToolbar {
                showActionToolbar(for: rect.integral)
            } else {
                onFinish?(rect.integral, nil)
            }
        } else {
            self.dragStart = nil
            pendingSnapRect = nil
            dragMode = .creating
            selectionRect = nil
            didDrag = false
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard dragStart == nil, actionToolbar == nil, !isTransitioning else { return }
        updateHoveredSnapTarget(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStart == nil, actionToolbar == nil else { return }
        hoveredSnapTarget = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelSelection()
    }

    func cancelSelection() {
        guard !isTransitioning else { return }
        removeActionToolbar()
        dragStart = nil
        dragMode = .creating
        pendingSnapRect = nil
        hoveredSnapTarget = nil
        selectionRect = nil
        needsDisplay = true
        onFinish?(nil, nil)
    }

    func prepareForDeferredDismissal() {
        isTransitioning = true
        removeActionToolbar()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelSelection()
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

        guard let displayRect = selectionRect ?? hoveredSnapTarget?.frame else {
            drawHint("拖动选择区域 · 右键 / Esc 取消", at: CGPoint(x: bounds.midX, y: bounds.midY))
            return
        }

        if showsPresetFixture {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(displayRect)
            drawPresetFixture(in: displayRect)
        } else {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(displayRect)
            context.restoreGState()
        }

        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(selectionRect == nil ? 1.5 : 2)
        context.stroke(displayRect.insetBy(dx: 1, dy: 1))

        if selectionRect != nil, showsActionToolbar {
            drawResizeHandles(around: displayRect, in: context)
        }

        let dimensions = "\(Int(displayRect.width)) × \(Int(displayRect.height))"
        drawHint(dimensions, at: CGPoint(x: displayRect.midX, y: max(26, displayRect.minY - 18)))
    }

    private func updateHoveredSnapTarget(at point: CGPoint) {
        let candidate = WindowSnapTargetSelector.target(at: point, from: snapTargets)
        guard candidate != hoveredSnapTarget else { return }
        hoveredSnapTarget = candidate
        needsDisplay = true
    }

    private func showActionToolbar(for selectionRect: CGRect) {
        removeActionToolbar()

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 7, bottom: 6, right: 7)

        for (index, item) in CaptureActionToolbarLayout.actions.enumerated() {
            if index == 4 || index == 6 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 22).isActive = true
                stack.addArrangedSubview(separator)
            }
            let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title) ?? NSImage()
            let configured = image.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? image
            let button = NSButton(image: configured, target: self, action: #selector(handleAction(_:)))
            button.tag = CaptureQuickAction.allCases.firstIndex(of: item.action) ?? index
            button.bezelStyle = .recessed
            button.controlSize = .regular
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = item.title
            button.setAccessibilityLabel(item.title)
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stack.addArrangedSubview(button)
        }

        let toolbar = NSVisualEffectView()
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 12
        toolbar.layer?.masksToBounds = true
        toolbar.addSubview(stack)

        let fittingSize = stack.fittingSize
        let toolbarSize = CGSize(width: fittingSize.width, height: max(44, fittingSize.height))
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

    private func resizeHandle(at point: CGPoint, for rect: CGRect) -> SelectionResizeHandle? {
        let hitRadius: CGFloat = 8
        return SelectionResizeHandle.allCases.first { handle in
            let target = handle.point(in: rect)
            return abs(point.x - target.x) <= hitRadius && abs(point.y - target.y) <= hitRadius
        }
    }

    private func drawResizeHandles(around rect: CGRect, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1.5)
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        for handle in SelectionResizeHandle.allCases {
            let point = handle.point(in: rect)
            let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.fillEllipse(in: handleRect)
            context.strokeEllipse(in: handleRect)
        }
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
