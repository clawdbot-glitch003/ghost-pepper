import XCTest
@testable import GhostPepper

final class TranscriptionOutputTests: XCTestCase {
    func testExternalKeyboardBridgeEncodesTextCommandAsJSONLine() throws {
        let transport = CapturingBridgeTransport(result: .success(()))
        let target = ExternalKeyboardBridgeOutputTarget(transport: transport)

        let result = target.deliver(text: "Hello \"bridge\" 🌶️")

        XCTAssertEqual(result, .sentToExternalKeyboardBridge)
        let sentData = try XCTUnwrap(transport.sentData)
        XCTAssertEqual(sentData.last, 0x0A)

        let payload = sentData.dropLast()
        let object = try JSONSerialization.jsonObject(with: Data(payload)) as? [String: String]
        XCTAssertEqual(object?["type"], "text")
        XCTAssertEqual(object?["text"], "Hello \"bridge\" 🌶️")
    }

    func testExternalKeyboardBridgeReportsTransportFailure() {
        let transport = CapturingBridgeTransport(
            result: .failure(ExternalKeyboardBridgeError.invalidConfiguration("No bridge."))
        )
        let target = ExternalKeyboardBridgeOutputTarget(transport: transport)

        let result = target.deliver(text: "Hello")

        XCTAssertEqual(result, .failed("External keyboard bridge failed: No bridge."))
    }
}

private final class CapturingBridgeTransport: ExternalKeyboardBridgeTransport {
    let result: Result<Void, Error>
    private(set) var sentData: Data?

    init(result: Result<Void, Error>) {
        self.result = result
    }

    func sendJSONLine(_ data: Data) -> Result<Void, Error> {
        sentData = data
        return result
    }
}
