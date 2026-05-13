import Darwin
import Foundation
import Network

/// User-facing destinations for completed, cleaned dictation text.
enum TranscriptionOutputMode: String, CaseIterable, Identifiable {
    case localPaste
    case usbSerialKeyboardBridge
    case networkKeyboardBridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localPaste:
            return "Local paste"
        case .usbSerialKeyboardBridge:
            return "USB serial keyboard bridge"
        case .networkKeyboardBridge:
            return "Network keyboard bridge"
        }
    }

    var description: String {
        switch self {
        case .localPaste:
            return "Paste into the focused app on this Mac."
        case .usbSerialKeyboardBridge:
            return "Send final text to an ESP32 BLE keyboard bridge over USB serial."
        case .networkKeyboardBridge:
            return "Send final text to a TCP keyboard bridge service as JSON lines."
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
    func deliver(text: String) async -> TranscriptionOutputResult
}

struct LocalPasteOutputTarget: TranscriptionOutputTarget {
    let textPaster: TextPaster

    func deliver(text: String) async -> TranscriptionOutputResult {
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
    func sendJSONLine(_ data: Data) async -> Result<Void, Error>
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

    func sendJSONLine(_ data: Data) async -> Result<Void, Error> {
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
        let sendState = ExternalKeyboardBridgeSendState()
        let timeoutWorkItem = DispatchWorkItem {
            sendState.finish(.failure(ExternalKeyboardBridgeError.timeout))
            connection.cancel()
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready where sendState.tryBeginSend():
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        sendState.finish(.failure(error))
                    } else {
                        sendState.finish(.success(()))
                    }
                    timeoutWorkItem.cancel()
                    connection.cancel()
                })
            case .failed(let error):
                sendState.finish(.failure(error))
                timeoutWorkItem.cancel()
                connection.cancel()
            default:
                break
            }
        }

        return await withCheckedContinuation { continuation in
            sendState.setContinuation(continuation)
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
            connection.start(queue: queue)
        }
    }
}

struct POSIXSerialExternalKeyboardBridgeTransport: ExternalKeyboardBridgeTransport {
    let devicePath: String
    let baudRate: speed_t

    init(devicePath: String, baudRate: speed_t = speed_t(B115200)) {
        self.devicePath = devicePath
        self.baudRate = baudRate
    }

    func sendJSONLine(_ data: Data) async -> Result<Void, Error> {
        let trimmedPath = devicePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return .failure(ExternalKeyboardBridgeError.invalidConfiguration("Serial device path is empty."))
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.write(data, to: trimmedPath, baudRate: baudRate))
            }
        }
    }

    private static func write(_ data: Data, to devicePath: String, baudRate: speed_t) -> Result<Void, Error> {
        let fd = devicePath.withCString { pathPointer in
            open(pathPointer, O_RDWR | O_NOCTTY | O_NONBLOCK)
        }
        guard fd >= 0 else {
            return .failure(POSIXSerialError.openFailed(path: devicePath, errnoCode: errno))
        }
        defer { close(fd) }

        if fcntl(fd, F_SETFL, 0) == -1 {
            return .failure(POSIXSerialError.configureFailed(path: devicePath, errnoCode: errno))
        }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            return .failure(POSIXSerialError.configureFailed(path: devicePath, errnoCode: errno))
        }

        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB)
        options.c_cflag |= tcflag_t(CS8)

        guard cfsetspeed(&options, baudRate) == 0,
              tcsetattr(fd, TCSANOW, &options) == 0 else {
            return .failure(POSIXSerialError.configureFailed(path: devicePath, errnoCode: errno))
        }

        let writeResult = data.withUnsafeBytes { rawBuffer -> Result<Void, Error> in
            guard let baseAddress = rawBuffer.baseAddress else { return .success(()) }
            var bytesWritten = 0
            while bytesWritten < rawBuffer.count {
                let result = Darwin.write(
                    fd,
                    baseAddress.advanced(by: bytesWritten),
                    rawBuffer.count - bytesWritten
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    return .failure(POSIXSerialError.writeFailed(path: devicePath, errnoCode: errno))
                }
                if result == 0 {
                    return .failure(POSIXSerialError.writeFailed(path: devicePath, errnoCode: EIO))
                }
                bytesWritten += result
            }
            return .success(())
        }

        guard case .success = writeResult else { return writeResult }
        guard tcdrain(fd) == 0 else {
            return .failure(POSIXSerialError.writeFailed(path: devicePath, errnoCode: errno))
        }
        return .success(())
    }
}

enum POSIXSerialError: LocalizedError, Equatable {
    case openFailed(path: String, errnoCode: Int32)
    case configureFailed(path: String, errnoCode: Int32)
    case writeFailed(path: String, errnoCode: Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let errnoCode):
            return "Could not open serial device \(path): \(String(cString: strerror(errnoCode)))."
        case .configureFailed(let path, let errnoCode):
            return "Could not configure serial device \(path) for 115200 8N1: \(String(cString: strerror(errnoCode)))."
        case .writeFailed(let path, let errnoCode):
            return "Could not write to serial device \(path): \(String(cString: strerror(errnoCode)))."
        }
    }
}

private final class ExternalKeyboardBridgeSendState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasStartedSend = false
    private var storedResult: Result<Void, Error>?
    private var continuation: CheckedContinuation<Result<Void, Error>, Never>?

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
        let continuationToResume: CheckedContinuation<Result<Void, Error>, Never>?
        lock.lock()
        guard storedResult == nil else {
            lock.unlock()
            return
        }
        storedResult = result
        continuationToResume = continuation
        continuation = nil
        lock.unlock()
        continuationToResume?.resume(returning: result)
    }

    func setContinuation(_ continuation: CheckedContinuation<Result<Void, Error>, Never>) {
        let resultToResume: Result<Void, Error>?
        lock.lock()
        if let storedResult {
            resultToResume = storedResult
        } else {
            self.continuation = continuation
            resultToResume = nil
        }
        lock.unlock()

        if let resultToResume {
            continuation.resume(returning: resultToResume)
        }
    }
}

struct ExternalKeyboardBridgeOutputTarget: TranscriptionOutputTarget {
    let transport: ExternalKeyboardBridgeTransport
    private let encoder: JSONEncoder

    init(transport: ExternalKeyboardBridgeTransport, encoder: JSONEncoder = JSONEncoder()) {
        self.transport = transport
        self.encoder = encoder
    }

    func deliver(text: String) async -> TranscriptionOutputResult {
        do {
            var data = try encoder.encode(ExternalKeyboardBridgeCommand(text: text))
            data.append(0x0A)
            switch await transport.sendJSONLine(data) {
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
    let bridgePort: Int
    let bridgeSerialPath: String
    let bridgeTransportFactory: (String, UInt16) -> ExternalKeyboardBridgeTransport
    let serialTransportFactory: (String) -> ExternalKeyboardBridgeTransport

    init(
        mode: TranscriptionOutputMode,
        textPaster: TextPaster,
        bridgeHost: String,
        bridgePort: Int,
        bridgeSerialPath: String = "",
        bridgeTransportFactory: @escaping (String, UInt16) -> ExternalKeyboardBridgeTransport = { host, port in
            TCPExternalKeyboardBridgeTransport(host: host, port: port)
        },
        serialTransportFactory: @escaping (String) -> ExternalKeyboardBridgeTransport = { path in
            POSIXSerialExternalKeyboardBridgeTransport(devicePath: path)
        }
    ) {
        self.mode = mode
        self.textPaster = textPaster
        self.bridgeHost = bridgeHost
        self.bridgePort = bridgePort
        self.bridgeSerialPath = bridgeSerialPath
        self.bridgeTransportFactory = bridgeTransportFactory
        self.serialTransportFactory = serialTransportFactory
    }

    func deliver(text: String) async -> TranscriptionOutputResult {
        switch mode {
        case .localPaste:
            return await LocalPasteOutputTarget(textPaster: textPaster).deliver(text: text)
        case .usbSerialKeyboardBridge:
            let trimmedPath = bridgeSerialPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                return .failed("External keyboard bridge failed: Serial device path is empty.")
            }
            let transport = serialTransportFactory(trimmedPath)
            return await ExternalKeyboardBridgeOutputTarget(transport: transport).deliver(text: text)
        case .networkKeyboardBridge:
            guard (1...65535).contains(bridgePort) else {
                return .failed("External keyboard bridge failed: Bridge port must be between 1 and 65535.")
            }
            let transport = bridgeTransportFactory(bridgeHost, UInt16(bridgePort))
            return await ExternalKeyboardBridgeOutputTarget(transport: transport).deliver(text: text)
        }
    }
}
