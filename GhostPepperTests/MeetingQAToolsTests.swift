import XCTest
@testable import GhostPepper

final class MeetingQAToolsTests: XCTestCase {
    private var rootDir: URL!

    override func setUpWithError() throws {
        rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingQAToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir.appendingPathComponent("2025-01-29"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootDir.appendingPathComponent("2026-01-07"), withIntermediateDirectories: true)
        try """
        ---
        title: "Denis <> Matt"
        date: "2025-01-29"
        ---

        # Denis <> Matt

        ## Summary
        Discussion about Neville Shaw and the fund.
        """.write(to: rootDir.appendingPathComponent("2025-01-29/denis-matt.md"), atomically: true, encoding: .utf8)

        try """
        # factorial-standup

        **Date:** 2026-01-07

        ## Notes
        Peter Pace - he's not a Neville Jun for 10 years. Trade ideas.
        """.write(to: rootDir.appendingPathComponent("2026-01-07/factorial-standup.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootDir)
    }

    // MARK: - grep

    func testGrepFindsMatchAcrossArchive() async throws {
        let tools = MeetingQATools(root: rootDir)
        let result = try await tools.grep(pattern: "Neville", path: nil, caseInsensitive: true, maxResults: 50)
        XCTAssertTrue(result.contains("2025-01-29/denis-matt.md:"), "Expected file:line match in output: \(result)")
        XCTAssertTrue(result.contains("2026-01-07/factorial-standup.md:"), "Expected second-file match in output: \(result)")
    }

    func testGrepRespectsMaxResults() async throws {
        let tools = MeetingQATools(root: rootDir)
        let result = try await tools.grep(pattern: "Neville", path: nil, caseInsensitive: true, maxResults: 1)
        let matchLines = result.split(separator: "\n").filter { $0.contains(".md:") }
        XCTAssertEqual(matchLines.count, 1, "Expected exactly 1 match line, got: \(result)")
        XCTAssertTrue(result.contains("max_results was 1"), "Expected hit-cap meta line: \(result)")
    }

    func testGrepReturnsNoMatchesMessage() async throws {
        let tools = MeetingQATools(root: rootDir)
        let result = try await tools.grep(pattern: "definitelynotinanyfile", path: nil, caseInsensitive: false, maxResults: 50)
        XCTAssertTrue(result.contains("No matches found"), result)
    }

    func testGrepRejectsPathOutsideRoot() async {
        let tools = MeetingQATools(root: rootDir)
        do {
            _ = try await tools.grep(pattern: "anything", path: "../outside", caseInsensitive: true, maxResults: 10)
            XCTFail("Expected pathOutsideRoot error")
        } catch let error as PathSandboxError {
            guard case .pathOutsideRoot = error else { XCTFail("Wrong error: \(error)"); return }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
