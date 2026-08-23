public struct ClipboardCommitPolicy: Sendable {
    public init() {}

    public func shouldCommit(
        initialChangeCount: Int,
        currentChangeCount: Int,
        jobIsLatest: Bool
    ) -> Bool {
        jobIsLatest && initialChangeCount == currentChangeCount
    }
}
