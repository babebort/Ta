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
      hudModel?.status = "Click Auto Scroll and grant permission to capture continuously from the top of the selection to the bottom"
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
                  hudModel?.status = "Scroll area hasn't reached the bottom yet, re-locking and continuing"
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
                  hudModel?.status = "Could not send scroll events to the capture target. Please check the target window and Accessibility permission"
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
    hudModel?.status = "Reached the bottom of the scroll area, Capture complete"
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
    let stickyStatusFragments = ["Capture complete", "Paused", "Could not send scroll events to the capture target"]
    let hasStickyStatus = stickyStatusFragments.contains { fragment in
      hudModel?.status.contains(fragment) ?? false
    }
    if !hasStickyStatus {
      if acceptedFrames <= 1, !isAutoScrolling {
        hudModel?.status = "Scroll manually, or turn on auto scroll"
      } else if isAutoScrolling, bottomConfirmationCount > 0 {
        hudModel?.status =
          "Reached the bottom, confirming the final frame · \(bottomConfirmationCount) / \(Self.requiredBottomConfirmationFrames)"
      } else if isAutoScrolling, autoScrollProgress.needsMoreSettlingTime,
        Date() < autoScrollSettleDeadline
      {
        hudModel?.status = "Page is still changing, waiting for it to settle"
      } else if isAutoScrolling, autoScrollProgress.attemptsWithoutProgress > 0 {
        hudModel?.status =
          "Waiting for the page to respond · Retried \(autoScrollProgress.attemptsWithoutProgress) / \(autoScrollProgress.maximumAttemptsWithoutProgress) times"
      } else {
        hudModel?.status =
          isAutoScrolling
          ? "Auto scrolling, detecting new content"
          : "Detecting overlap area and fixed input fields"
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
    hudModel?.status = isPaused ? "Paused, you can review the content" : "Resuming scroll"
  }

  private func toggleAutoScroll() {
    if isAutoScrolling {
      isAutoScrolling = false
      autoScrollProgress.begin()
      hudModel?.isAutoScrolling = false
      hudModel?.status = "Auto scroll turned off, you can keep scrolling manually"
      return
    }
    guard AccessibilityAutoScrollService.isGranted || AccessibilityAutoScrollService.request()
    else {
      hudModel?.status = "Auto scroll requires Accessibility permission; click again after granting it"
      return
    }
    guard let activeSelection else {
      hudModel?.status = "The capture area is no longer valid. Please start a new scrolling capture"
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
      ? "Locked the scroll area, capturing automatically to the real bottom"
      : "General scroll mode, detecting new content automatically until the frame settles"
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
  @Published var status = "Capturing the first frame…"
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
          Text("Capturing scrolling screenshot")
            .font(.headline)
          Text(model.status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(model.acceptedFrames) frames · \(model.pixelHeight) px")
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        Text(model.skippedFrames > 0 ? "Skipped \(model.skippedFrames) discontinuous frames" : "Slow, continuous scrolling works best")
          .font(.caption2)
          .foregroundStyle(model.skippedFrames > 0 ? .orange : .secondary)
        Spacer()
        Button(model.isAutoScrolling ? "Stop Auto Scroll" : "Auto Scroll") { model.onToggleAutoScroll?() }
        Button(model.isPaused ? "Resume" : "Pause") { model.onTogglePause?() }
        Button("Cancel") { model.onCancel?() }
        Button("Finish & Save") { model.onFinish?() }
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
