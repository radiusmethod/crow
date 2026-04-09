import CrowIPC
import Foundation

enum RPCError: Error, LocalizedError, RPCErrorCoded {
    case invalidParams(String)
    case applicationError(String)
    var rpcErrorCode: Int {
        switch self {
        case .invalidParams: RPCErrorCode.invalidParams
        case .applicationError: RPCErrorCode.applicationError
        }
    }
    var errorDescription: String? {
        switch self {
        case .invalidParams(let msg): msg
        case .applicationError(let msg): msg
        }
    }
}
