import Foundation

/// Tracks content progress per emitted scroll gesture rather than per capture
/// tick. Slow animation may produce many duplicate frames, but those frames
/// still belong to one attempt and cannot exhaust the bottom-detection budget.
public struct AutoScrollProgressTracker: Sendable {
    public let maximumAttemptsWithoutProgress: Int
    public private(set) var attemptsWithoutProgress = 0
    public private(set) var hasPendingScroll = false
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
        hasPendingScroll && pendingScrollSawInconclusiveFrame
    }

    public mutating func begin() {
        attemptsWithoutProgress = 0
        hasPendingScroll = false
        pendingScrollSawInconclusiveFrame = false
    }

    /// Opens exactly one scroll attempt. A second gesture must never be sent
    /// until this attempt is resolved as progress or no movement.
    public mutating func didSendScroll() {
        guard !hasPendingScroll else { return }
        hasPendingScroll = true
        pendingScrollSawInconclusiveFrame = false
    }

    public mutating func observe(_ disposition: ScrollingFrameDisposition) {
        guard hasPendingScroll else { return }
        if case .appended = disposition {
            attemptsWithoutProgress = 0
            hasPendingScroll = false
            pendingScrollSawInconclusiveFrame = false
        } else if case .rejected = disposition {
            pendingScrollSawInconclusiveFrame = true
        }
    }

    /// Call only after the settle deadline and only when the accepted viewport
    /// is still unchanged. A matcher failure after visible movement is not the
    /// bottom and must not consume this budget.
    public mutating func finishPendingWithoutProgress() {
        guard hasPendingScroll else { return }
        attemptsWithoutProgress += 1
        hasPendingScroll = false
        pendingScrollSawInconclusiveFrame = false
    }

    /// Closes a gesture when movement was confirmed independently from seam
    /// matching (for example by AX scrollbar progress or viewport pixels).
    /// Stitching quality must never hold the scroll driver hostage.
    public mutating func finishPendingWithProgress() {
        guard hasPendingScroll else { return }
        attemptsWithoutProgress = 0
        hasPendingScroll = false
        pendingScrollSawInconclusiveFrame = false
    }

    /// Clears a gesture that was deliberately rolled back for seam recovery.
    /// A recovered gesture is not evidence of the bottom and must not consume
    /// the no-progress budget.
    public mutating func cancelPendingAttempt() {
        hasPendingScroll = false
        pendingScrollSawInconclusiveFrame = false
    }
}
