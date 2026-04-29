import Foundation

/// Streaming events emitted by `IndexBuilder` during a build or update.
enum IndexBuildEvent {
    case estimating
    case estimated(IndexBuildEstimate)
    /// Status line update: e.g. "Reading 2026-04-28/standup.md"
    case status(String)
    case entryWritten(slug: String, canonicalName: String)
    case usage(QAUsage)
    case completed
    case error(String)
}

struct IndexBuildEstimate {
    let meetingCount: Int
    let existingEntryCount: Int
    let likelyLowUSD: Double
    let likelyHighUSD: Double
    let modelDisplayName: String

    var isResume: Bool { existingEntryCount > 0 }
}
