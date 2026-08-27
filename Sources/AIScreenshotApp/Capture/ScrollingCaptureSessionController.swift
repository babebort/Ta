import AIScreenshotCore
import AppKit
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
  private let bottomFrameMotionDetector = ViewportMotionDetector()
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
  private var activeSelection: CaptureSelection?
  private var scrollTarget: AccessibilityScrollTarget?
  private var pendingScrollProgress: AccessibilityScrollProgress?
  private var expectedScrollDistancePoints = 0
  private var autoScrollProgress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 3)
  private var nextAutoScrollDate = Date.distantPast
  private var autoScrollSettleDeadline = Date.distantPast
  private var bottomConfirmationCount = 0
  static let standardAutoScrollDelayMilliseconds = 300
  static let standardAutoScrollDelay: TimeInterval = 0.30
  static let maximumAutoScrollSettleTime: TimeInterval = 1.20
  static let requiredBottomConfirmationFrames = 3

  enum AutoScrollAttemptResolution: Equatable {
    case waiting
    case progress
    case noMovement
  }

  func start(
    selection: CaptureSelection,
    completion: @escaping (ScrollingCaptureSessionOutcome) -> Void
  ) {
    cancel(notify: false)
    stitcher.reset()
    viewportMotionDetector.reset()
    bottomFrameMotionDetector.reset()
    acceptedFrames = 0
    skippedFrames = 0
    isPaused = false
    isFinishing = false
    isAutoScrolling = false
    autoScrollProgress.begin()
    activeSelection = selection
    scrollTarget = nil
    pendingScrollProgress = nil
    expectedScrollDistancePoints = Self.recommendedScrollDistance(for: selection)
    bottomConfirmationCount = 0
    nextAutoScrollDate = .distantPast
    autoScrollSettleDeadline = .distantPast
    self.completion = completion
    showHUD(near: selection)
    if AccessibilityAutoScrollService.isGranted {
      beginAutoScroll(selection: selection)
    } else {
      hudModel?.status = "点击自动滚动并授权后，将从选区顶部持续采集到底部"
    }

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
          let requestedPixelShift = Int(
            (Double(max(1, expectedScrollDistancePoints))
              * selection.backingScaleFactor).rounded()
          )
          var disposition = try stitcher.append(
            image,
            constraint: isAutoScrolling ? .downwardOnly : .any,
            preferredPixelShift: isAutoScrolling ? requestedPixelShift : nil
          )
          if isAutoScrolling {
            let now = Date()
            let currentScrollProgress = scrollTarget.flatMap {
              AccessibilityAutoScrollService.progress(of: $0)
            }
            let bottomFrameMotion: ViewportMotionMeasurement?
            if currentScrollProgress?.isAtEnd == true {
              bottomFrameMotion = try bottomFrameMotionDetector.compare(image)
              try bottomFrameMotionDetector.commit(image)
            } else {
              bottomFrameMotionDetector.reset()
              bottomFrameMotion = nil
            }
            let observation = Self.autoScrollObservation(
              stitchDisposition: disposition,
              motion: motion
            )
            autoScrollProgress.observe(observation)
            switch Self.resolveAutoScrollAttempt(
              progress: autoScrollProgress,
              observation: observation,
              motion: motion,
              scrollProgressBefore: pendingScrollProgress,
              scrollProgressAfter: currentScrollProgress,
              now: now,
              settleDeadline: autoScrollSettleDeadline
            ) {
            case .waiting:
              break
            case .progress:
              // Scrollbar movement and viewport movement are independent
              // proof that the gesture succeeded. If the seam is ambiguous,
              // keep a conservative low-confidence frame and continue; never
              // let the stitcher stop the scroll driver after one gesture.
              if autoScrollProgress.hasPendingScroll {
                switch disposition {
                case .firstFrame, .appended:
                  break
                case .duplicate, .rejected:
                  // The final wheel gesture is often shorter than the regular
                  // step. Wait for the bottom viewport to settle, then measure
                  // that exact tail instead of inserting a full-size fallback.
                  if currentScrollProgress?.isAtEnd != true {
                    disposition = try stitcher.appendFallback(
                      image,
                      signedPixelShift: requestedPixelShift
                    )
                  }
                }
              }
              autoScrollProgress.finishPendingWithProgress()
              pendingScrollProgress = nil
              expectedScrollDistancePoints = Self.recommendedScrollDistance(for: selection)
              nextAutoScrollDate = now.addingTimeInterval(Self.standardAutoScrollDelay)
            case .noMovement:
              autoScrollProgress.finishPendingWithoutProgress()
              pendingScrollProgress = nil
            }

            // AX can report its maximum before smooth scrolling, lazy loading,
            // or composer relayout finishes. Once two consecutive bottom
            // captures are stable, commit the settled terminal viewport. This
            // preserves a short final scroll that is smaller than the normal
            // step and would otherwise be omitted from the stitched image.
            if currentScrollProgress?.isAtEnd == true,
              bottomFrameMotion?.hasReference == true,
              bottomFrameMotion?.isStationary == true
            {
              switch disposition {
              case .firstFrame, .appended:
                break
              case .duplicate, .rejected:
                disposition = try stitcher.appendTerminalFrame(
                  image,
                  preferredPixelShift: requestedPixelShift
                )
              }
            }
            bottomConfirmationCount = Self.advanceBottomConfirmation(
              currentCount: bottomConfirmationCount,
              observation: disposition,
              motion: bottomFrameMotion,
              scrollProgressAfter: currentScrollProgress
            )
            if isAutoScrolling,
              bottomConfirmationCount >= Self.requiredBottomConfirmationFrames
            {
              stopAutoScrollAtBottom()
            }

            if isAutoScrolling,
              !autoScrollProgress.hasPendingScroll,
              now >= nextAutoScrollDate
            {
              if autoScrollProgress.shouldStop {
                if Self.shouldCompleteAfterNoProgress(
                  progress: autoScrollProgress,
                  targetMode: scrollTarget?.mode ?? .eventFallback,
                  currentScrollProgress: currentScrollProgress
                ) {
                  stopAutoScrollAtBottom()
                } else {
                  // The viewport looked stationary, but the tracked scrollbar
                  // still says there is content below. Re-resolve the nested
                  // scroll area and retry with a smaller step instead of
                  // incorrectly declaring the capture complete.
                  scrollTarget = AccessibilityAutoScrollService.resolveTarget(for: selection)
                  autoScrollProgress.begin()
                  pendingScrollProgress = nil
                  expectedScrollDistancePoints = max(
                    96,
                    Self.recommendedScrollDistance(for: selection) / 2
                  )
                  nextAutoScrollDate = now.addingTimeInterval(Self.standardAutoScrollDelay)
                  hudModel?.status = "滚动区域仍未到底，正在重新锁定并继续"
                }
              } else if currentScrollProgress?.isAtEnd == true {
                // Do not open another gesture after a bottom signal;
                // pixel stability controls completion from here.
                nextAutoScrollDate = .distantFuture
              } else {
                let distance = min(
                  Self.recommendedScrollDistance(for: selection),
                  max(96, expectedScrollDistancePoints)
                )
                let before = scrollTarget.flatMap {
                  AccessibilityAutoScrollService.progress(of: $0)
                }
                if await AccessibilityAutoScrollService.postDownwardScroll(
                  in: selection,
                  target: scrollTarget,
                  pixels: distance
                ) {
                  autoScrollProgress.didSendScroll()
                  pendingScrollProgress = before
                  expectedScrollDistancePoints = distance
                  nextAutoScrollDate = now.addingTimeInterval(Self.standardAutoScrollDelay)
                  autoScrollSettleDeadline = now.addingTimeInterval(
                    Self.maximumAutoScrollSettleTime)
                } else {
                  isAutoScrolling = false
                  hudModel?.isAutoScrolling = false
                  hudModel?.status = "无法向截图目标发送滚动事件，请检查目标窗口与辅助功能权限"
                }
              }
            }
          }
          switch disposition {
          case .firstFrame:
            acceptedFrames = 1
            try viewportMotionDetector.commit(image)
          case .appended:
            acceptedFrames += 1
            try viewportMotionDetector.commit(image)
          case .duplicate:
            break
          case .rejected:
            skippedFrames += 1
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
    min(460, max(120, Int((selection.globalRect.height * 0.42).rounded())))
  }

  static func resolveAutoScrollAttempt(
    progress: AutoScrollProgressTracker,
    observation: ScrollingFrameDisposition,
    motion: ViewportMotionMeasurement,
    scrollProgressBefore: AccessibilityScrollProgress? = nil,
    scrollProgressAfter: AccessibilityScrollProgress? = nil,
    now: Date,
    settleDeadline: Date
  ) -> AutoScrollAttemptResolution {
    guard progress.hasPendingScroll else {
      if case .appended = observation { return .progress }
      return .waiting
    }
    if case .appended = observation { return .progress }
    let trackedProgressAdvanced = AccessibilityAutoScrollService.progressAdvanced(
      from: scrollProgressBefore,
      to: scrollProgressAfter
    )
    if trackedProgressAdvanced { return .progress }
    if motion.hasReference, !motion.isStationary { return .progress }
    guard now >= settleDeadline else { return .waiting }
    return .noMovement
  }

  static func advanceBottomConfirmation(
    currentCount: Int,
    observation: ScrollingFrameDisposition,
    motion: ViewportMotionMeasurement?,
    scrollProgressAfter: AccessibilityScrollProgress?,
    requiredCount: Int = ScrollingCaptureSessionController.requiredBottomConfirmationFrames
  ) -> Int {
    guard scrollProgressAfter?.isAtEnd == true, requiredCount > 0 else { return 0 }

    // The scrollbar can reach its maximum while the last wheel animation is
    // still revealing content. Only consecutive bottom frames that are stable
    // relative to each other may confirm completion.
    if case .appended = observation { return 0 }
    guard motion?.hasReference == true, motion?.isStationary == true else { return 0 }

    return min(requiredCount, currentCount + 1)
  }

  static func shouldCompleteAfterNoProgress(
    progress: AutoScrollProgressTracker,
    targetMode: AccessibilityScrollTarget.Mode,
    currentScrollProgress: AccessibilityScrollProgress?
  ) -> Bool {
    guard progress.shouldStop else { return false }
    if let currentScrollProgress {
      return currentScrollProgress.isAtEnd
    }
    return targetMode == .eventFallback
  }

  private func stopAutoScrollAtBottom() {
    isAutoScrolling = false
    autoScrollProgress.begin()
    pendingScrollProgress = nil
    bottomConfirmationCount = 0
    hudModel?.isAutoScrolling = false
    hudModel?.status = "已到达滚动区域底部，内容采集完成"
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
    let screen =
      NSScreen.screens.first(where: { $0.frame.intersects(selection.globalRect) })
      ?? NSScreen.main
      ?? NSScreen.screens[0]
    let visible = screen.visibleFrame
    let x = min(
      max(visible.minX + 12, selection.globalRect.midX - size.width / 2),
      visible.maxX - size.width - 12)
    let below = selection.globalRect.minY - size.height - 12
    let y =
      below >= visible.minY + 8
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
    let stickyStatusFragments = ["内容采集完成", "已暂停", "无法向截图目标发送滚动事件"]
    let hasStickyStatus = stickyStatusFragments.contains { fragment in
      hudModel?.status.contains(fragment) ?? false
    }
    if !hasStickyStatus {
      if acceptedFrames <= 1, !isAutoScrolling {
        hudModel?.status = "可手动上下滚动，也可开启自动滚动"
      } else if isAutoScrolling, bottomConfirmationCount > 0 {
        hudModel?.status =
          "已到底，正在确认最终画面 · \(bottomConfirmationCount) / \(Self.requiredBottomConfirmationFrames)"
      } else if isAutoScrolling, autoScrollProgress.needsMoreSettlingTime,
        Date() < autoScrollSettleDeadline
      {
        hudModel?.status = "页面仍在变化，等待稳定后继续"
      } else if isAutoScrolling, autoScrollProgress.attemptsWithoutProgress > 0 {
        hudModel?.status =
          "等待页面响应 · 已重试 \(autoScrollProgress.attemptsWithoutProgress) / \(autoScrollProgress.maximumAttemptsWithoutProgress) 次"
      } else {
        hudModel?.status =
          isAutoScrolling
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
    guard AccessibilityAutoScrollService.isGranted || AccessibilityAutoScrollService.request()
    else {
      hudModel?.status = "自动滚动需要辅助功能权限；授权后再次点击"
      return
    }
    guard let activeSelection else {
      hudModel?.status = "截图区域已经失效，请重新开始长截图"
      return
    }
    beginAutoScroll(selection: activeSelection)
  }

  private func beginAutoScroll(selection: CaptureSelection) {
    let resolvedTarget = AccessibilityAutoScrollService.resolveTarget(for: selection)
    scrollTarget = resolvedTarget
    isAutoScrolling = true
    autoScrollProgress.begin()
    nextAutoScrollDate = Date()
    autoScrollSettleDeadline = .distantPast
    hudModel?.isAutoScrolling = true
    hudModel?.status =
      resolvedTarget.mode == .accessibilityTracked
      ? "已锁定滚动区域，自动采集到真实底部"
      : "通用滚动模式，自动识别新增内容直到画面稳定"
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
    let completion = self.completion
    self.completion = nil
    let outcome = ScrollingCaptureSessionOutcome.completed(
      images: images,
      acceptedFrames: acceptedFrames,
      skippedFrames: skippedFrames,
      reviewedSeams: reviewedSeams
    )
    releaseCapturedFrames()
    completion?(outcome)
  }

  private func fail(_ error: Error) {
    captureTask?.cancel()
    captureTask = nil
    closeHUD()
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    let completion = self.completion
    self.completion = nil
    releaseCapturedFrames()
    completion?(.failed(message))
  }

  private func cancel(notify: Bool) {
    captureTask?.cancel()
    captureTask = nil
    closeHUD()
    seamReview.close()
    releaseCapturedFrames()
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

  private func releaseCapturedFrames() {
    stitcher.reset()
    viewportMotionDetector.reset()
    bottomFrameMotionDetector.reset()
    activeSelection = nil
    scrollTarget = nil
    pendingScrollProgress = nil
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
