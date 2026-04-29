import Foundation

/// One entry in an index — e.g. one person's dossier under `.indexes/people/<slug>.md`.
/// Persisted as markdown with YAML frontmatter; see `IndexEntryFile` for the file format.
struct IndexEntry: Equatable {
    let kind: IndexKind
    var canonicalName: String
    var aliases: [String]
    var sourceMeetings: [String]
    var lastUpdated: Date
    var body: String

    var slug: String { MarkdownArchivePaths.slugForIndexEntry(canonicalName) }
}
