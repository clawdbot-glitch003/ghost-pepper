import SwiftUI

/// Modal sheet that estimates the cost of building an index, then streams
/// progress while the agent builds it. Closes on completion or cancel.
struct BuildIndexSheet: View {
    let kind: IndexKind
    let builder: IndexBuilder
    let onClose: () -> Void

    @State private var phase: Phase = .estimating
    @State private var estimate: IndexBuildEstimate?
    @State private var statusLine: String = ""
    @State private var entriesWritten: Int = 0
    @State private var runningCost: Double = 0
    @State private var errorMessage: String?
    @State private var buildTask: Task<Void, Never>?

    enum Phase {
        case estimating
        case readyToBuild
        case building
        case completed
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: kind.iconSystemName)
                    .font(.system(size: 16))
                Text("Build \(kind.displayName) index")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            switch phase {
            case .estimating:
                estimatingView
            case .readyToBuild:
                readyView
            case .building:
                buildingView
            case .completed:
                completedView
            case .failed:
                failedView
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await runEstimate()
        }
    }

    private var estimatingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Estimating cost…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private var readyView: some View {
        if let estimate {
            VStack(alignment: .leading, spacing: 12) {
                if estimate.isResume {
                    Text("**Existing index detected** (\(estimate.existingEntryCount) entries). The agent will read each existing dossier before writing, so this run **appends and updates** rather than starting over.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                }

                Text("This will scan **\(estimate.meetingCount)** meetings using **\(estimate.modelDisplayName)**.")
                    .font(.system(size: 13))

                Text("Likely cost: \(formatCost(estimate.likelyLowUSD)) – \(formatCost(estimate.likelyHighUSD))")
                    .font(.system(size: 13, weight: .medium))

                Text("Estimate is order-of-magnitude; running cost is shown during the build, and you can hit Stop at any time. Switch to Haiku in Settings → Cross-Meeting Q&A → Model for ~3× cheaper.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Cancel", action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Button(estimate.isResume ? "Resume" : "Build") {
                        runBuild()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
    }

    private var buildingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text(statusLine.isEmpty ? "Building…" : statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 16) {
                Label("\(entriesWritten) entries", systemImage: "doc.text")
                Label(formatCost(runningCost), systemImage: "dollarsign.circle")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Stop") {
                    buildTask?.cancel()
                }
            }
        }
    }

    private var completedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Built \(entriesWritten) entries")
                    .font(.system(size: 13, weight: .medium))
            }
            Text("Total cost: \(formatCost(runningCost))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
    }

    private var failedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Build failed")
                    .font(.system(size: 13, weight: .medium))
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: - Actions

    private func runEstimate() async {
        do {
            let est = try await builder.estimateBuildCost(kind: kind)
            self.estimate = est
            self.phase = .readyToBuild
        } catch {
            self.errorMessage = "Couldn't estimate cost: \(error.localizedDescription)"
            self.phase = .failed
        }
    }

    private func runBuild() {
        phase = .building
        statusLine = "Starting…"
        entriesWritten = 0
        runningCost = 0
        let task = Task { @MainActor in
            do {
                for try await event in builder.buildFullIndex(kind: kind) {
                    if Task.isCancelled { break }
                    switch event {
                    case .estimating, .estimated:
                        break
                    case .status(let s):
                        statusLine = s
                    case .entryWritten:
                        entriesWritten += 1
                    case .usage(let u):
                        runningCost = u.estimatedCostUSD
                    case .completed:
                        phase = .completed
                        return
                    case .error(let msg):
                        errorMessage = msg
                        phase = .failed
                        return
                    }
                }
                if Task.isCancelled {
                    phase = .completed
                }
            } catch {
                errorMessage = error.localizedDescription
                phase = .failed
            }
        }
        buildTask = task
    }

    private func formatCost(_ cost: Double) -> String {
        String(format: "$%.4f", cost)
    }
}
