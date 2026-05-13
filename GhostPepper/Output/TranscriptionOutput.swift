import Foundation
import Network

/// User-facing destinations for completed, cleaned dictation text.
enum TranscriptionOutputMode: String, CaseIterable, Identifiable {
    case localPaste
    case externalKeyboardBridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localPaste:
            return "Local paste"
        case .externalKeyboardBridge:
            return "External keyboard bridge"
        }
    }

    var description: String {
        switch self {
        case .localPaste:
            return "Paste into the focused app on this Mac."
        case .externalKeyboardBridge:
            return "Send final text to a HID bridge device/service as JSON lines."
        }
    }
}

enum TranscriptionOutputResult: Equatable {
    case pasted
    case copiedToClipboard
    case sentToExternalKeyboardBridge
    case failed(String)
}

protocol TranscriptionOutputTarget {
    func deliver(text: String) -> TranscriptionOutputResult
}

struct LocalPasteOutputTarget: TranscriptionOutputTarget {
    let textPaster: TextPaster

    func deliver(text: String) -> TranscriptionOutputResult {
        switch textPaster.paste(text: text) {
        case .pasted:
            return .pasted
        case .copiedToClipboard:
            return .copiedToClipboard
        }
    }
}

struct ExternalKeyboardBridgeCommand: Encodable, Equatable {
    let type: String
    let text: String

    init(text: String) {
        self.type = "text"
        self.text = text
    }
}

protocol ExternalKeyboardBridgeTransport {
    func sendJSONLine(_ data: Data) -> Result<Void, Error>
}

struct TCPExternalKeyboardBridgeTransport: ExternalKeyboardBridgeTransport {
    let host: String
    let port: UInt16
    let timeout: TimeInterval

    init(host: String, port: UInt16, timeout: TimeInterval = 2.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    func sendJSONLine(_ data: Data) -> Result<Void, Error> {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(ExternalKeyboardBridgeError.invalidConfiguration("Bridge host is empty."))
        }

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return .failure(ExternalKeyboardBridgeError.invalidConfiguration("Bridge port must be between 1 and 65535."))
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        let queue = DispatchQueue(label: "GhostPepper.ExternalKeyboardBridgeTransport")
        let semaphore = DispatchSemaphore(value: 0)
        let sendState = ExternalKeyboardBridgeSendState()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready where sendState.tryBeginSend():
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        sendState.finish(.failure(error))
                    } else {
                        sendState.finish(.success(()))
                    }
                    connection.cancel()
                    semaphore.signal()
                })
            case .failed(let error):
                sendState.finish(.failure(error))
                connection.cancel()
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: queue)
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            connection.cancel()
            return .failure(ExternalKeyboardBridgeError.timeout)
        }

        return sendState.result ?? .failure(ExternalKeyboardBridgeError.unknown)
    }
}

private final class ExternalKeyboardBridgeSendState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasStartedSend = false
    private var storedResult: Result<Void, Error>?

    var result: Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func tryBeginSend() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasStartedSend else { return false }
        hasStartedSend = true
        return true
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}

struct ExternalKeyboardBridgeOutputTarget: TranscriptionOutputTarget {
    let transport: ExternalKeyboardBridgeTransport
    private let encoder: JSONEncoder

    init(transport: ExternalKeyboardBridgeTransport, encoder: JSONEncoder = JSONEncoder()) {
        self.transport = transport
        self.encoder = encoder
    }

    func deliver(text: String) -> TranscriptionOutputResult {
        do {
            var data = try encoder.encode(ExternalKeyboardBridgeCommand(text: text))
            data.append(0x0A)
            switch transport.sendJSONLine(data) {
            case .success:
                return .sentToExternalKeyboardBridge
            case .failure(let error):
                return .failed("External keyboard bridge failed: \(error.localizedDescription)")
            }
        } catch {
            return .failed("External keyboard bridge command encoding failed: \(error.localizedDescription)")
        }
    }
}

enum ExternalKeyboardBridgeError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case timeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .timeout:
            return "Timed out connecting to the external keyboard bridge."
        case .unknown:
            return "The external keyboard bridge did not report a result."
        }
    }
}

struct TranscriptionOutputRouter {
    let mode: TranscriptionOutputMode
    let textPaster: TextPaster
    let bridgeHost: String
    let bridgePort: UInt16
    let bridgeTransportFactory: (String, UInt16) -> ExternalKeyboardBridgeTransport

    init(
        mode: TranscriptionOutputMode,
        textPaster: TextPaster,
        bridgeHost: String,
        bridgePort: UInt16,
        bridgeTransportFactory: @escaping (String, UInt16) -> ExternalKeyboardBridgeTransport = { host, port in
            TCPExternalKeyboardBridgeTransport(host: host, port: port)
        }
    ) {
        self.mode = mode
        self.textPaster = textPaster
        self.bridgeHost = bridgeHost
        self.bridgePort = bridgePort
        self.bridgeTransportFactory = bridgeTransportFactory
    }

    func deliver(text: String) -> TranscriptionOutputResult {
        switch mode {
        case .localPaste:
            return LocalPasteOutputTarget(textPaster: textPaster).deliver(text: text)
        case .externalKeyboardBridge:
            let transport = bridgeTransportFactory(bridgeHost, bridgePort)
            return ExternalKeyboardBridgeOutputTarget(transport: transport).deliver(text: text)
        }
    }
}
