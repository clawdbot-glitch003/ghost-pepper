import SwiftUI

/// Cmd+K command palette. Live-filters across People (index entries),
/// Meetings (recorded / imported markdown), and Notes (quick-note files).
/// ↑/↓ moves the highlight; Enter opens the highlighted result; Esc dismisses.
struct CommandKSearchSheet: View {
    @ObservedObject var state: MeetingWindowState
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    private var results: CommandKResults {
        CommandKResults.compute(state: state, query: query)
    }

    /// Flat list across all three sections in the order they're rendered, so
    /// arrow-key navigation lines up with what the user sees.
    private var flatItems: [CommandKItem] {
        results.people + results.meetings + results.notes
    }

    private var clampedIndex: Int {
        guard !flatItems.isEmpty else { return 0 }
        return max(0, min(selectedIndex, flatItems.count - 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsBody
        }
        .frame(width: 620)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onKeyPress(.upArrow) {
            guard !flatItems.isEmpty else { return .ignored }
            selectedIndex = max(0, clampedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !flatItems.isEmpty else { return .ignored }
            selectedIndex = min(flatItems.count - 1, clampedIndex + 1)
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Search people, meetings, notes…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($fieldFocused)
                .onSubmit { activateSelected() }
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            keyHint("↑↓")
            keyHint("⏎")
            Button(action: { isPresented = false }) {
                Text("ESC")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func keyHint(_ glyph: String) -> some View {
        Text(glyph)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(3)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if results.totalCount == 0 {
            VStack(spacing: 6) {
                Image(systemName: query.isEmpty ? "magnifyingglass" : "questionmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(query.isEmpty ? "Type to search across people, meetings, and notes."
                                   : "No matches for \"\(query)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        section(title: "People", icon: "person.3", items: results.people)
                        section(title: "Meetings", icon: "doc.text", items: results.meetings)
                        section(title: "Notes", icon: "note.text", items: results.notes)
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 440)
                .onChange(of: clampedIndex) { _, idx in
                    guard idx < flatItems.count else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(flatItems[idx].id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, icon: String, items: [CommandKItem]) -> some View {
        if !items.isEmpty {
            Text("\(title) (\(items.count))")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                resultRow(item: item, icon: icon)
                    .id(item.id)
            }
        }
    }

    private func resultRow(item: CommandKItem, icon: String) -> some View {
        let isSelected = flatItems.indices.contains(clampedIndex) && flatItems[clampedIndex].id == item.id
        return Button(action: { activate(item) }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13))
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.orange.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering, let idx = flatItems.firstIndex(where: { $0.id == item.id }) {
                selectedIndex = idx
            }
        }
    }

    private func activate(_ item: CommandKItem) {
        item.activate(state)
        isPresented = false
    }

    private func activateSelected() {
        guard !flatItems.isEmpty else { return }
        let idx = clampedIndex
        guard flatItems.indices.contains(idx) else { return }
        activate(flatItems[idx])
    }
}

// MARK: - Result types

struct CommandKItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let activate: (MeetingWindowState) -> Void
}

struct CommandKResults {
    var people: [CommandKItem]
    var meetings: [CommandKItem]
    var notes: [CommandKItem]

    var totalCount: Int { people.count + meetings.count + notes.count }

    private static let perSectionLimit = 12

    @MainActor
    static func compute(state: MeetingWindowState, query: String) -> CommandKResults {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return .init(people: [], meetings: [], notes: [])
        }

        // People
        var people: [CommandKItem] = []
        for (kind, items) in state.indexItems {
            for item in items where matches(item.canonicalName, needle: needle) {
                let captured = item
                people.append(CommandKItem(
                    id: "person-\(kind.rawValue)-\(captured.slug)",
                    title: captured.canonicalName,
                    subtitle: kind.displayName,
                    activate: { st in st.openIndexEntry(kind: captured.kind, slug: captured.slug) }
                ))
            }
        }
        people.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        // Meetings + notes — split by filename prefix.
        var meetings: [CommandKItem] = []
        var notes: [CommandKItem] = []
        for group in state.historyGroups {
            for entry in group.entries where matches(entry.name, needle: needle) || group.date.lowercased().contains(needle) {
                let isNote = entry.fileURL.lastPathComponent.hasPrefix("quick-note")
                let captured = entry
                let item = CommandKItem(
                    id: "file-\(captured.fileURL.path)",
                    title: captured.name,
                    subtitle: group.date,
                    activate: { st in st.openFile(captured.fileURL) }
                )
                if isNote {
                    notes.append(item)
                } else {
                    meetings.append(item)
                }
            }
        }

        return .init(
            people: Array(people.prefix(perSectionLimit)),
            meetings: Array(meetings.prefix(perSectionLimit)),
            notes: Array(notes.prefix(perSectionLimit))
        )
    }

    private static func matches(_ haystack: String, needle: String) -> Bool {
        haystack.lowercased().contains(needle)
    }
}
