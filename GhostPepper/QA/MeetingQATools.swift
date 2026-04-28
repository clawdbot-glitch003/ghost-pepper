import Foundation

enum MeetingQAToolError: LocalizedError {
    case grepFailed(String)
    case readFailed(String)
    case timedOut(String)
    case notADirectory(String)
    case fileNotFound(String)
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .grepFailed(let m): return "grep failed: \(m)"
        case .readFailed(let m): return "read failed: \(m)"
        case .timedOut(let what): return "\(what) timed out after 30s. Narrow scope and retry."
        case .notADirectory(let p): return "Not a directory: \(p)"
        case .fileNotFound(let p): return "File not found: \(p)"
        case .invalidArguments(let m): return "Invalid arguments: \(m)"
        }
    }
}

struct MeetingQATools {
    let root: URL
    private let timeout: TimeInterval = 30

    init(root: URL) {
        self.root = root
    }

    // MARK: - grep

    func grep(pattern: String, path: String?, caseInsensitive: Bool, maxResults: Int) async throws -> String {
        let searchURL: URL
        if let path = path, !path.isEmpty, path != "." {
            searchURL = try PathSandbox.resolveSafe(path, root: root)
        } else {
            searchURL = root
        }

        let binary = Self.preferredGrepBinary()
        var args: [String] = ["-r", "-n", "--include=*.md", "--exclude-dir=.git"]
        if caseInsensitive { args.append("-i") }
        args.append("-e")
        args.append(pattern)
        args.append(searchURL.path)

        let result = try await runProcess(launchPath: binary, arguments: args)
        if result.exitCode > 1 {
            throw MeetingQAToolError.grepFailed(result.stderr.isEmpty ? "exit \(result.exitCode)" : result.stderr)
        }
        if result.exitCode == 1 {
            return "No matches found for pattern: \(pattern)"
        }

        let allLines = result.stdout.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
        let totalMatches = allLines.count
        let cap = max(1, min(maxResults, 200))
        let truncated = allLines.prefix(cap)
        let rebased = truncated.map { line -> String in
            if line.hasPrefix(root.path + "/") {
                return String(line.dropFirst(root.path.count + 1))
            }
            return line
        }
        var output = rebased.joined(separator: "\n")
        if !output.isEmpty { output += "\n" }
        if totalMatches > cap {
            output += "\n(Returned \(cap) matches; max_results was \(cap) and was hit. Increase max_results or narrow scope to see more.)"
        } else {
            output += "\n(Returned \(totalMatches) of \(totalMatches) matches.)"
        }
        return output
    }

    // MARK: - Process plumbing

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func runProcess(launchPath: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var didResume = false
            let resumeLock = NSLock()
            func resumeOnce(_ block: () -> Void) {
                resumeLock.lock(); defer { resumeLock.unlock() }
                guard !didResume else { return }
                didResume = true
                block()
            }

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                    resumeOnce { continuation.resume(throwing: MeetingQAToolError.timedOut("grep")) }
                }
            }
            timer.resume()

            process.terminationHandler = { p in
                timer.cancel()
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                resumeOnce { continuation.resume(returning: ProcessResult(stdout: stdout, stderr: stderr, exitCode: p.terminationStatus)) }
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                resumeOnce { continuation.resume(throwing: error) }
            }
        }
    }

    private static func preferredGrepBinary() -> String {
        let candidates = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return "/usr/bin/grep"
    }
}
