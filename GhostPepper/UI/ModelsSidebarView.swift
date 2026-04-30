import SwiftUI

/// Right-side panel showing what Ghost Pepper does, which model is doing it,
/// and the full toolkit of local + cloud models. Read-only — downloads,
/// keychain edits, and model selection happen in Settings.
struct ModelsSidebarView: View {
    @AppStorage("speechModel") private var selectedSpeechModelID: String = SpeechModelCatalog.defaultModelID
    @AppStorage("selectedCleanupModelKind") private var selectedCleanupModelKindRaw: String = LocalCleanupModelKind.qwen35_0_8b_q4_k_m.rawValue
    @AppStorage("claudeAPIModel") private var selectedClaudeModelRaw: String = ClaudeAPIModel.sonnet.rawValue

    @State private var refreshTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 12).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    functionsSection
                    localModelsSection
                    cloudModelsSection
                    footer
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .id(refreshTick)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Models")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { refreshTick += 1 }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Re-check status")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Section 1 · Functions

    private var functionsSection: some View {
        section(title: "What Ghost Pepper does") {
            FunctionRowPicker(
                icon: "waveform",
                title: "Speech-to-text",
                location: .local,
                isEmpty: downloadedSpeechModels.isEmpty,
                emptyMessage: "Download a speech model in Settings → Models"
            ) {
                Picker("", selection: $selectedSpeechModelID) {
                    ForEach(downloadedSpeechModels, id: \.id) { model in
                        Text(model.pickerTitle).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            FunctionRow(
                icon: "person.wave.2",
                title: "Speaker diarization",
                modelLabel: diarizationLabel,
                location: .local,
                available: diarizationAvailable
            )

            FunctionRowPicker(
                icon: "sparkles",
                title: "Cleanup",
                location: .local,
                isEmpty: downloadedCleanupModels.isEmpty,
                emptyMessage: "Download a cleanup model in Settings → Models"
            ) {
                Picker("", selection: $selectedCleanupModelKindRaw) {
                    ForEach(downloadedCleanupModels, id: \.kind) { desc in
                        Text(desc.displayName).tag(desc.kind.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            FunctionRow(
                icon: "doc.text",
                title: "Meeting summary",
                modelLabel: (cleanupModel?.displayName ?? "—") + " (same as Cleanup)",
                location: .local,
                available: cleanupModel.map { TextCleanupManager.isModelDownloaded($0.kind) } ?? false
            )

            FunctionRowPicker(
                icon: "cpu",
                title: "Agent (Q&A · indexing)",
                location: .cloud,
                isEmpty: !hasClaudeKey,
                emptyMessage: "Add an API key in Settings → Cross-Meeting Q&A"
            ) {
                Picker("", selection: $selectedClaudeModelRaw) {
                    ForEach(ClaudeAPIModel.allCases) { model in
                        Text(model.shortDisplayName).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    /// Speech models the user has actually downloaded — only these can drive
    /// speech-to-text, so the picker is filtered to them.
    private var downloadedSpeechModels: [SpeechModelDescriptor] {
        SpeechModelCatalog.availableModels.filter { ModelManager.isCached($0) }
    }

    /// Cleanup models the user has actually downloaded.
    private var downloadedCleanupModels: [CleanupModelDescriptor] {
        TextCleanupManager.cleanupModels.filter { TextCleanupManager.isModelDownloaded($0.kind) }
    }

    // MARK: - Section 2 · Local models

    private var localModelsSection: some View {
        section(title: "Local models") {
            ForEach(SpeechModelCatalog.availableModels, id: \.id) { model in
                LocalModelRow(
                    title: model.pickerTitle,
                    subtitle: "\(model.variantName) · \(model.sizeDescription)",
                    capabilities: capabilities(for: model),
                    isDownloaded: ModelManager.isCached(model),
                    isActive: model.id == selectedSpeechModelID
                )
            }
            ForEach(TextCleanupManager.cleanupModels, id: \.kind) { desc in
                LocalModelRow(
                    title: desc.displayName,
                    subtitle: desc.sizeDescription,
                    capabilities: ["cleanup", "meeting summary"],
                    isDownloaded: TextCleanupManager.isModelDownloaded(desc.kind),
                    isActive: desc.kind.rawValue == selectedCleanupModelKindRaw
                )
            }
        }
    }

    // MARK: - Section 3 · Cloud models

    private var cloudModelsSection: some View {
        section(title: "Cloud models") {
            HStack(spacing: 6) {
                Circle()
                    .fill(hasClaudeKey ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(hasClaudeKey
                     ? "Anthropic API key configured"
                     : "Anthropic API key not set")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)

            ForEach(ClaudeAPIModel.allCases) { model in
                LocalModelRow(
                    title: model.shortDisplayName,
                    subtitle: model.rawValue,
                    capabilities: ["agent (Q&A · indexing)"],
                    isDownloaded: hasClaudeKey,
                    isActive: hasClaudeKey && model.rawValue == selectedClaudeModelRaw
                )
            }

            if !hasClaudeKey {
                Text("Add a key in Settings → Meeting Transcript → Cross-Meeting Q&A.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("Most of Ghost Pepper runs 100% on-device.")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text("Cloud models are optional and live in your Keychain.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Resolved selections

    private var speechModel: SpeechModelDescriptor? {
        SpeechModelCatalog.model(named: selectedSpeechModelID)
    }

    private var cleanupModel: CleanupModelDescriptor? {
        TextCleanupManager.cleanupModels.first { $0.kind.rawValue == selectedCleanupModelKindRaw }
    }

    private var claudeModel: ClaudeAPIModel {
        ClaudeAPIModel(rawValue: selectedClaudeModelRaw) ?? .sonnet
    }

    private var hasClaudeKey: Bool {
        (KeychainHelper.get(AnthropicProvider.keychainKey) ?? "").isEmpty == false
    }

    private var diarizationLabel: String {
        if let m = speechModel, m.supportsSpeakerFiltering {
            return m.pickerTitle
        }
        return "needs a FluidAudio model"
    }

    private var diarizationAvailable: Bool {
        guard let m = speechModel, m.supportsSpeakerFiltering else { return false }
        return ModelManager.isCached(m)
    }

    private func capabilities(for model: SpeechModelDescriptor) -> [String] {
        var caps = ["speech-to-text"]
        if model.supportsSpeakerFiltering { caps.append("diarization") }
        return caps
    }

    // MARK: - Section wrapper

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }
}

// MARK: - Rows

private enum ModelLocation { case local, cloud }

/// FunctionRow variant that hosts a Picker (or any inline selector view) on
/// the secondary line. The picker is constrained to choices the user can
/// actually use — caller filters to downloaded local models or to cloud
/// models with an API key.
private struct FunctionRowPicker<Picker: View>: View {
    let icon: String
    let title: String
    let location: ModelLocation
    /// If true, the picker is shown disabled and a small hint replaces the
    /// secondary line so the user knows where to go to fix it.
    let isEmpty: Bool
    let emptyMessage: String
    @ViewBuilder let picker: () -> Picker

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text(location == .local ? "local" : "cloud")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(location == .local ? .green : .blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background((location == .local ? Color.green : Color.blue).opacity(0.12))
                        .cornerRadius(3)
                }
                if isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    picker()
                        .frame(maxWidth: 220)
                        .controlSize(.small)
                }
            }
            Spacer()
        }
    }
}

private struct FunctionRow: View {
    let icon: String
    let title: String
    let modelLabel: String
    let location: ModelLocation
    let available: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                HStack(spacing: 4) {
                    Text(modelLabel)
                        .font(.system(size: 11))
                        .foregroundColor(available ? .secondary : .red.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(location == .local ? "local" : "cloud")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(location == .local ? .green : .blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (location == .local ? Color.green : Color.blue).opacity(0.12)
                        )
                        .cornerRadius(3)
                }
            }
            Spacer()
        }
    }
}

private struct LocalModelRow: View {
    let title: String
    let subtitle: String
    let capabilities: [String]
    let isDownloaded: Bool
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isDownloaded ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isDownloaded ? .primary : .secondary)
                    if isActive {
                        Text("active")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }
                    if !isDownloaded {
                        Text("not downloaded")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(capabilities.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.85))
            }
            Spacer()
        }
    }
}
