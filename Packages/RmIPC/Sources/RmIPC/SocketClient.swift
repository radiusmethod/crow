import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Unix domain socket client for sending JSON-RPC requests.
public struct SocketClient: Sendable {
    private let socketPath: String

    public init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? {
            // RIDE_SOCKET overrides for hook subprocesses (legacy support)
            if let override = ProcessInfo.processInfo.environment["RIDE_SOCKET"] {
                return override
            }
            return SocketServer.defaultSocketPath()
        }()
    }

    /// Send a JSON-RPC request and return the response.
    public func send(method: String, params: [String: JSONValue] = [:]) throws -> JSONRPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SocketError.createFailed(errno)
        }
        defer { close(fd) }

        // Connect
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    _ = strlcpy(dest, ptr, 104)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw SocketError.connectionFailed(errno)
        }

        // Send request
        let request = JSONRPCRequest(id: 1, method: method, params: params.isEmpty ? nil : params)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(request)
        data.append(UInt8(ascii: "\n"))

        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }

        // Read response until newline
        var responseData = Data()
        var byte: UInt8 = 0
        while true {
            let bytesRead = read(fd, &byte, 1)
            if bytesRead <= 0 { break }
            if byte == UInt8(ascii: "\n") { break }
            responseData.append(byte)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(JSONRPCResponse.self, from: responseData)
    }
}
