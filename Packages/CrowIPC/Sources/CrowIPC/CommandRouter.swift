import Foundation

/// Routes JSON-RPC method names to handler closures.
public final class CommandRouter: Sendable {
    public typealias Handler = @Sendable ([String: JSONValue]) async throws -> [String: JSONValue]

    private let handlers: [String: Handler]

    public init(handlers: [String: Handler]) {
        self.handlers = handlers
    }

    public func handle(request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let handler = handlers[request.method] else {
            return .error(id: request.id, code: RPCErrorCode.methodNotFound, message: "Unknown method: \(request.method)")
        }

        do {
            let result = try await handler(request.params ?? [:])
            return .success(id: request.id, result: result)
        } catch {
            return .error(id: request.id, code: RPCErrorCode.applicationError, message: error.localizedDescription)
        }
    }
}
