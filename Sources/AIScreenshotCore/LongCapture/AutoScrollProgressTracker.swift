import Foundation

/// Tracks content progress per emitted scroll gesture rather than per capture
/// tick. Slow animation may produce many duplicate frames, but those frames
/// still belong to one attempt and cannot exhaust the bottom-detection budget.
public struct AutoScrollProgressTracker: Sendable {
    public let maximumAttemptsWithoutProgress: Int
    public private(set) var attemptsWithoutProgress = 0
    private var hasPendingScroll = false
    private var pendingScrollMadeProgress = false
    private var pendingScrollSawInconclusiveFrame = false

    public init(maximumAttemptsWithoutProgress: Int = 2) {
        self.maximumAttemptsWithoutProgress = max(1, maximumAttemptsWithoutProgress)
    }

    public var shouldStop: Bool {
        attemptsWithoutProgress >= maximumAttemptsWithoutProgress
    }

    /// A rejected match can mean the page is still animating rather than that
    /// the scroll failed. Give that attempt a bounded settling window before
    /// consuming another retry.
    public var needsMoreSettlingTime: Bool {
        hasPendingScroll && !pendingScrollMadeProgress && pendingScrollSawInconclusiveFrame
    }

    public mutating func begin() {
        attemptsWithoutProgress = 0
        hasPendingScroll = false
        pendingScrollMadeProgress = false
        pendingScrollSawInconclusiveFrame = false
    }

    /// Finalizes the preceding attempt, then opens a new one. Callers should
    /// inspect `shouldStop` immediately afterwards and avoid sending the newly
    /// opened scroll when the previous attempts have reached the limit.
    public mutating func didSendScroll() {
        if hasPendingScroll {
            if pendingScrollMadeProgress {
                attemptsWithoutProgress = 0
            } else {
                attemptsWithoutProgress += 1
            }
        }
        hasPendingScroll = true
        pendingScrollMadeProgress = false
        pendingScrollSawInconclusiveFrame = false
    }

    public mutating func observe(_ disposition: ScrollingFrameDisposition) {
        guard hasPendingScroll else { return }
        if case .appended = disposition {
            pendingScrollMadeProgress = true
            attemptsWithoutProgress = 0
        } else if case .rejected = disposition {
            pendingScrollSawInconclusiveFrame = true
        }
    }
}
