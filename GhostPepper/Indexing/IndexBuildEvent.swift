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
    let inputTokens: Int
    /// Conservative cost in USD assuming output is 30% of input.
    let estimatedCostUSD: Double
    /// Upper-bound multiplier label, e.g. "could be up to 3x for large archives".
    var upperBoundCostUSD: Double { estimatedCostUSD * 3 }
}
