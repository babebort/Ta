import AppKit
import AIScreenshotCore
import SwiftUI

enum ScrollingCaptureSessionOutcome {
    case cancelled
    case completed(images: [CGImage], acceptedFrames: Int, skippedFrames: Int, reviewedSeams: Int)
    case failed(String)
}

@MainActor
final class ScrollingCaptureSessionController {
    private let captureService = ScreenCaptureService()
    private let stitcher = ScrollingImageStitcher()
    private let viewportMotionDetector = ViewportMotionDetector()
    private let seamReview = ScrollingSeamReviewWindowController()
    private var captureTask: Task<Void, Never>?
    private var panel: NSPanel?
    private var hudModel: ScrollingCaptureHUDModel?
    private var completion: ((ScrollingCaptureSessionOutcome) -> Void)?
    private var acceptedFrames = 0
    private var skippedFrames = 0
    private var isPaused = false
    private var isFinishing = false
    private var isAutoScrolling = false
    private var autoScrollProgress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    private var nextAutoScrollDate = Date.distantPast
    private var autoScrollSettleDeadline = Date.distantPast
    static let standardAutoScrollDelayMilliseconds = 300
    static let standardAutoScrollDelay: TimeInterval = 0.30
    static let maximumAutoScrollSettleTime: TimeInterval = 0.90

    func start(
        selection: CaptureSelection,
        completion: @escaping (ScrollingCaptureSessionOutcome) -> Void
    ) {
        cancel(notify: false)
        stitcher.reset()
        viewportMotionDetector.reset()
        acceptedFrames = 0
        skippedFrames = 0
        isPaused = false
        isFinishing = false
        isAutoScrolling = false
        autoScrollProgress.begin()
        nextAutoScrollDate = .distantPast
        autoScrollSettleDeadline = .distantPast
        self.completion = completion
        showHUD(near: selection)

        captureTask = Task { [weak self] in
            guard let self else { return }
            await captureLoop(selection: selection)
        }
    }

    private func captureLoop(selection: CaptureSelection) async {
        while !Task.isCancelled, !isFinishing {
            if !isPaused {
                do {
                    let image = try await captureService.capture(selection)
                    guard !Task.isCancelled else { return }
                    let motion = try viewportMotionDetector.compare(image)
                    let disposition = try stitcher.append(image)
                    switch disposition {
                    case .firstFrame:
                        acceptedFrames = 1
                    case .appended:
                        acceptedFrames += 1
                    case .duplicate:
                        break
                    case .rejected:
                        skippedFrames += 1
                    }
                    if case .firstFrame = disposition {
                        try viewportMotionDetector.commit(image)
                    } else if case .appended = disposition {
                        try viewportMotionDetector.commit(image)
                    }
                    if isAutoScrolling {
                        autoScrollProgress.observe(
                            Self.autoScrollObservation(
                                stitchDisposition: disposition,
                                motion: motion
                            )
                        )
                        let now = Date()
                        if now >= nextAutoScrollDate,
                           !Self.shouldDeferAutoScrollRetry(
                            progress: autoScrollProgress,
                            now: now,
                            settleDeadline: autoScrollSettleDeadline
                           ) {
                            autoScrollProgress.didSendScroll()
                            if autoScrollProgress.shouldStop {
                                isAutoScrolling = false
                                hudModel?.isAutoScrolling = false
                                hudModel?.status = "连续 \(autoScrollProgress.maximumAttemptsWithoutProgress) 次滚动没有新增内容，已停止自动滚动"
                            } else {
                                let distance = Self.recommendedScrollDistance(for: selection)
                                if AccessibilityAutoScrollService.postDownwardScroll(
                                    in: selection,
                                    pixels: distance
                                ) {
                                    nextAutoScrollDate = now.addingTimeInterval(Self.standardAutoScrollDelay)
                                    autoScrollSettleDeadline = now.addingTimeInterval(Self.maximumAutoScrollSettleTime)
                                } else {
                                    isAutoScrolling = false
                                    hudModel?.isAutoScrolling = false
                                    hudModel?.status = "无法向截图目标发送滚动事件，请检查目标窗口与辅助功能权限"
                                }
                            }
                        }
                    }
                    updateHUD()
                } catch is CancellationError {
                    return
                } catch {
                    fail(error)
                    return
                }
            }
            let loopDelay = isAutoScrolling ? Self.standardAutoScrollDelayMilliseconds : 420
            try? await Task.sleep(for: .milliseconds(loopDelay))
        }
    }

    static func recommendedScrollDistance(for selection: CaptureSelection) -> Int {
        min(520, max(180, Int((selection.globalRect.height * 0.48).rounded())))
    }

    static func shouldDeferAutoScrollRetry(
        progress: AutoScrollProgressTracker,
        now: Date,
        settleDeadline: Date
    ) -> Bool {
        progress.needsMoreSettlingTime && now < settleDeadline
    }

    static func autoScrollObservation(
        stitchDisposition: ScrollingFrameDisposition,
        motion: ViewportMotionMeasurement
    ) -> ScrollingFrameDisposition {
        if case .appended = stitchDisposition {
            return stitchDisposition
        }
        guard motion.hasReference else { return stitchDisposition }
        if motion.isStationary {
            return .duplicate
        }
        // The viewport visibly moved, but the seam matcher has not accepted a
        // stable frame yet. This is inconclusive, not evidence of the bottom.
        return .rejected
    }

    private func showHUD(near selection: CaptureSelection) {
        let model = ScrollingCaptureHUDModel()
        model.onTogglePause = { [weak self] in self?.togglePause() }
        model.onToggleAutoScroll = { [weak self] in self?.toggleAutoScroll() }
        model.onFinish = { [weak self] in self?.finish() }
        model.onCancel = { [weak self] in self?.cancel(notify: true) }
        hudModel = model

        let size = CGSize(width: 520, height: 124)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(selection.globalRect) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = min(max(visible.minX + 12, selection.globalRect.midX - size.width / 2),
                    visible.maxX - size.width - 12)
        let below = selection.globalRect.minY - size.height - 12
        let y = below >= visible.minY + 8
            ? below
            : min(visible.maxY - size.height - 8, selection.globalRect.maxY + 12)

        let panel = ScrollingCaptureHUDPanel(
            contentRect: CGRect(origin: CGPoint(x: x, y: y), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: ScrollingCaptureHUDView(model: model))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func updateHUD() {
        hudModel?.acceptedFrames = acceptedFrames
        hudModel?.skippedFrames = skippedFrames
        hudModel?.pixelHeight = stitcher.outputPixelHeight
        if !(hudModel?.status.contains("已停止自动滚动") ?? false),
           !(hudModel?.status.contains("无法发送滚动事件") ?? false) {
            if acceptedFrames <= 1, !isAutoScrolling {
                hudModel?.status = "可手动上下滚动，也可开启自动滚动"
            } else if isAutoScrolling, autoScrollProgress.needsMoreSettlingTime,
                      Date() < autoScrollSettleDeadline {
                hudModel?.status = "页面仍在变化，等待稳定后继续"
            } else if isAutoScrolling, autoScrollProgress.attemptsWithoutProgress > 0 {
                hudModel?.status = "等待页面响应 · 已重试 \(autoScrollProgress.attemptsWithoutProgress) / \(autoScrollProgress.maximumAttemptsWithoutProgress) 次"
            } else {
                hudModel?.status = isAutoScrolling
                    ? "自动滚动中，正在识别新增内容"
                    : "正在识别重叠区域与固定输入框"
            }
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if !isPaused, isAutoScrolling {
            autoScrollProgress.begin()
            nextAutoScrollDate = Date()
            autoScrollSettleDeadline = .distantPast
        }
        hudModel?.isPaused = isPaused
        hudModel?.status = isPaused ? "已暂停，可检查内容" : "继续上下滚动"
    }

    private func toggleAutoScroll() {
        if isAutoScrolling {
            isAutoScrolling = false
            autoScrollProgress.begin()
            hudModel?.isAutoScrolling = false
            hudModel?.status = "自动滚动已关闭，可继续手动滚动"
            return
        }
        guard AccessibilityAutoScrollService.isGranted || AccessibilityAutoScrollService.request() else {
            hudModel?.status = "自动滚动需要辅助功能权限；授权后再次点击"
            return
        }
        isAutoScrolling = true
        autoScrollProgress.begin()
        nextAutoScrollDate = Date()
        autoScrollSettleDeadline = .distantPast
        hudModel?.isAutoScrolling = true
        hudModel?.status = "自动滚动中；鼠标无需停在截图区域"
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        captureTask?.cancel()
        captureTask = nil
        closeHUD()
        guard !stitcher.segments.isEmpty else {
            do {
                complete(images: try stitcher.makeImages(maximumPixelHeight: 30_000), reviewedSeams: 0)
            } catch {
                fail(error)
            }
            return
        }
        seamReview.present(
            stitcher: stitcher,
            onComplete: { [weak self] images, reviewedSeams in
                self?.complete(images: images, reviewedSeams: reviewedSeams)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                stitcher.reset()
                let completion = self.completion
                self.completion = nil
                completion?(.cancelled)
            }
        )
    }

    private func complete(images: [CGImage], reviewedSeams: Int) {
        do {
            let completion = self.completion
            self.completion = nil
            completion?(.completed(
                images: images,
                acceptedFrames: acceptedFrames,
                skippedFrames: skippedFrames,
                reviewedSeams: reviewedSeams
            ))
        }
    }

    private func fail(_ error: Error) {
        captureTask?.cancel()
        captureTask = nil
        closeHUD()
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let completion = self.completion
        self.completion = nil
        completion?(.failed(message))
    }

    private func cancel(notify: Bool) {
        captureTask?.cancel()
        captureTask = nil
        closeHUD()
        seamReview.close()
        stitcher.reset()
        viewportMotionDetector.reset()
        if notify {
            let completion = self.completion
            self.completion = nil
            completion?(.cancelled)
        } else {
            completion = nil
        }
    }

    private func closeHUD() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hudModel = nil
    }
}

@MainActor
private final class ScrollingCaptureHUDModel: ObservableObject {
    @Published var status = "正在采集第一帧…"
    @Published var acceptedFrames = 0
    @Published var skippedFrames = 0
    @Published var pixelHeight = 0
    @Published var isPaused = false
    @Published var isAutoScrolling = false
    var onTogglePause: (() -> Void)?
    var onToggleAutoScroll: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
}

private struct ScrollingCaptureHUDView: View {
    @ObservedObject var model: ScrollingCaptureHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: model.isPaused ? "pause.circle.fill" : "arrow.up.arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(model.isPaused ? .orange : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("长截图采集中")
                        .font(.headline)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.acceptedFrames) 帧 · \(model.pixelHeight) px")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(model.skippedFrames > 0 ? "已跳过 \(model.skippedFrames) 个不连续画面" : "慢速、连续滚动效果最好")
                    .font(.caption2)
                    .foregroundStyle(model.skippedFrames > 0 ? .orange : .secondary)
                Spacer()
                Button(model.isAutoScrolling ? "停止自动滚动" : "自动滚动") { model.onToggleAutoScroll?() }
                Button(model.isPaused ? "继续" : "暂停") { model.onTogglePause?() }
                Button("取消") { model.onCancel?() }
                Button("完成并保存") { model.onFinish?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.acceptedFrames == 0)
            }
        }
        .padding(14)
        .frame(width: 520, height: 124)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18))
        }
    }
}

private final class ScrollingCaptureHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
