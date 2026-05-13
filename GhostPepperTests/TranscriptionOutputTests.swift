import XCTest
@testable import GhostPepper

final class TranscriptionOutputTests: XCTestCase {
    func testExternalKeyboardBridgeEncodesTextCommandAsJSONLine() async throws {
        let transport = CapturingBridgeTransport(result: .success(()))
        let target = ExternalKeyboardBridgeOutputTarget(transport: transport)

        let result = await target.deliver(text: "Hello \"bridge\" 🌶️")

        XCTAssertEqual(result, .sentToExternalKeyboardBridge)
        let sentData = try XCTUnwrap(transport.sentData)
        XCTAssertEqual(sentData.last, 0x0A)

        let payload = sentData.dropLast()
        let object = try JSONSerialization.jsonObject(with: Data(payload)) as? [String: String]
        XCTAssertEqual(object?["type"], "text")
        XCTAssertEqual(object?["text"], "Hello \"bridge\" 🌶️")
    }

    func testExternalKeyboardBridgeReportsTransportFailure() async {
        let transport = CapturingBridgeTransport(
            result: .failure(ExternalKeyboardBridgeError.invalidConfiguration("No bridge."))
        )
        let target = ExternalKeyboardBridgeOutputTarget(transport: transport)

        let result = await target.deliver(text: "Hello")

        XCTAssertEqual(result, .failed("External keyboard bridge failed: No bridge."))
    }

    func testNetworkKeyboardBridgeRejectsInvalidPortsWithoutClamping() async {
        var factoryWasCalled = false
        let router = TranscriptionOutputRouter(
            mode: .networkKeyboardBridge,
            textPaster: TextPaster(),
            bridgeHost: "127.0.0.1",
            bridgePort: 70000,
            bridgeTransportFactory: { _, _ in
                factoryWasCalled = true
                return CapturingBridgeTransport(result: .success(()))
            }
        )

        let result = await router.deliver(text: "Hello")

        XCTAssertEqual(result, .failed("External keyboard bridge failed: Bridge port must be between 1 and 65535."))
        XCTAssertFalse(factoryWasCalled)
    }

    func testUSBSerialKeyboardBridgeRejectsEmptySerialPathWithoutOpeningTransport() async {
        var factoryWasCalled = false
        let router = TranscriptionOutputRouter(
            mode: .usbSerialKeyboardBridge,
            textPaster: TextPaster(),
            bridgeHost: "127.0.0.1",
            bridgePort: 8765,
            bridgeSerialPath: "  ",
            serialTransportFactory: { _ in
                factoryWasCalled = true
                return CapturingBridgeTransport(result: .success(()))
            }
        )

        let result = await router.deliver(text: "Hello")

        XCTAssertEqual(result, .failed("External keyboard bridge failed: Serial device path is empty."))
        XCTAssertFalse(factoryWasCalled)
    }

    func testUSBSerialKeyboardBridgeRoutesToSerialTransportWithTrimmedPath() async {
        var capturedPath: String?
        let transport = CapturingBridgeTransport(result: .success(()))
        let router = TranscriptionOutputRouter(
            mode: .usbSerialKeyboardBridge,
            textPaster: TextPaster(),
            bridgeHost: "127.0.0.1",
            bridgePort: 8765,
            bridgeSerialPath: "  /dev/cu.usbserial-0001\n",
            serialTransportFactory: { path in
                capturedPath = path
                return transport
            }
        )

        let result = await router.deliver(text: "Hello")

        XCTAssertEqual(result, .sentToExternalKeyboardBridge)
        XCTAssertEqual(capturedPath, "/dev/cu.usbserial-0001")
        XCTAssertNotNil(transport.sentData)
    }
}

private final class CapturingBridgeTransport: ExternalKeyboardBridgeTransport {
    let result: Result<Void, Error>
    private(set) var sentData: Data?

    init(result: Result<Void, Error>) {
        self.result = result
    }

    func sendJSONLine(_ data: Data) async -> Result<Void, Error> {
        sentData = data
        return result
    }
}
