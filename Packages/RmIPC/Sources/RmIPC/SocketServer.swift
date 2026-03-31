import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Unix domain socket server that accepts JSON-RPC connections.
public final class SocketServer: @unchecked Sendable {
    private let socketPath: String
    private let router: CommandRouter
    private var serverFD: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "com.radiusmethod.ride.socket", qos: .userInitiated)

    public init(socketPath: String? = nil, router: CommandRouter) {
        self.socketPath = socketPath ?? {
            let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
            return (tmpDir as NSString).appendingPathComponent("ride.sock")
        }()
        self.router = router
    }

    public var path: String { socketPath }

    // MARK: - Start / Stop

    public func start() throws {
        // Remove stale socket
        unlink(socketPath)

        // Create socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw SocketError.createFailed(errno)
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    _ = strlcpy(dest, ptr, 104)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            throw SocketError.bindFailed(errno)
        }

        // Listen
        guard listen(serverFD, 5) == 0 else {
            close(serverFD)
            throw SocketError.listenFailed(errno)
        }

        running = true

        // Accept loop on background queue
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        running = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while running {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else {
                if running { continue }
                return
            }

            // Handle each client connection on a separate queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        // Read until newline
        var buffer = Data()
        var byte: UInt8 = 0

        while true {
            let bytesRead = read(fd, &byte, 1)
            if bytesRead <= 0 { return }
            if byte == UInt8(ascii: "\n") { break }
            buffer.append(byte)
        }

        guard !buffer.isEmpty else { return }

        // Parse JSON-RPC request
        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(JSONRPCRequest.self, from: buffer) else {
            let errorResponse = JSONRPCResponse.error(id: 0, code: RPCErrorCode.parseError, message: "Invalid JSON")
            writeResponse(errorResponse, to: fd)
            return
        }

        // Route to handler (async bridge)
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var response: JSONRPCResponse?
        let capturedRouter = router
        let capturedRequest = request

        Task {
            response = await capturedRouter.handle(request: capturedRequest)
            semaphore.signal()
        }

        semaphore.wait()

        if let response {
            writeResponse(response, to: fd)
        }
    }

    private func writeResponse(_ response: JSONRPCResponse, to fd: Int32) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(response) else { return }
        data.append(UInt8(ascii: "\n"))
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }
    }
}

public enum SocketError: Error, LocalizedError {
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectionFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .createFailed(let e): "Socket create failed: \(String(cString: strerror(e)))"
        case .bindFailed(let e): "Socket bind failed: \(String(cString: strerror(e)))"
        case .listenFailed(let e): "Socket listen failed: \(String(cString: strerror(e)))"
        case .connectionFailed(let e): "Socket connection failed: \(String(cString: strerror(e)))"
        }
    }
}
