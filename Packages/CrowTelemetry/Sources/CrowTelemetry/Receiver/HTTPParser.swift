import Foundation

/// A parsed HTTP/1.1 request.
struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Get a header value (case-insensitive lookup).
    func header(_ name: String) -> String? {
        let lower = name.lowercased()
        for (key, value) in headers {
            if key.lowercased() == lower { return value }
        }
        return nil
    }

    /// Content-Length from headers, or 0 if absent.
    var contentLength: Int {
        guard let value = header("Content-Length"), let length = Int(value) else { return 0 }
        return length
    }
}

/// Minimal HTTP/1.1 response builder.
struct HTTPResponse: Sendable {
    let statusCode: Int
    let statusText: String
    let body: Data

    static func ok(body: Data = Data("{}".utf8)) -> HTTPResponse {
        HTTPResponse(statusCode: 200, statusText: "OK", body: body)
    }

    static func badRequest(message: String = "Bad Request") -> HTTPResponse {
        HTTPResponse(statusCode: 400, statusText: "Bad Request",
                     body: Data("{\"error\":\"\(message)\"}".utf8))
    }

    static func notFound() -> HTTPResponse {
        HTTPResponse(statusCode: 404, statusText: "Not Found",
                     body: Data("{\"error\":\"Not Found\"}".utf8))
    }

    /// Serialize to HTTP/1.1 response bytes.
    func serialize() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        var data = Data(response.utf8)
        data.append(body)
        return data
    }
}

/// Minimal HTTP/1.1 request parser for OTLP payloads.
///
/// Only handles simple POST requests with Content-Length (no chunked encoding,
/// no keep-alive). This is sufficient for OTLP HTTP/JSON clients.
enum HTTPParser {

    /// Parse result from feeding data into the parser.
    enum ParseResult: Sendable {
        /// A complete request was parsed.
        case complete(HTTPRequest)
        /// More data is needed (headers not complete or body incomplete).
        case needsMore
        /// The data is malformed.
        case error(String)
    }

    /// Attempt to parse a complete HTTP request from the accumulated data.
    ///
    /// - Parameter data: All data received so far on the connection.
    /// - Returns: Parse result indicating complete, needs more data, or error.
    static func parse(_ data: Data) -> ParseResult {
        // Find the end of headers (double CRLF)
        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = data.range(of: separator) else {
            // Check for unreasonably large headers (> 8KB without end)
            if data.count > 8192 {
                return .error("Headers too large")
            }
            return .needsMore
        }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .error("Invalid header encoding")
        }

        // Parse request line and headers
        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return .error("Missing request line")
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            return .error("Malformed request line")
        }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Determine body length
        let bodyStart = separatorRange.upperBound
        let contentLength: Int
        if let cl = headers.first(where: { $0.key.lowercased() == "content-length" })?.value,
           let len = Int(cl) {
            contentLength = len
        } else {
            contentLength = 0
        }

        // Check if we have the full body
        let bodyAvailable = data.count - data.distance(from: data.startIndex, to: bodyStart)
        if bodyAvailable < contentLength {
            return .needsMore
        }

        let body = data[bodyStart..<data.index(bodyStart, offsetBy: contentLength)]

        return .complete(HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: Data(body)
        ))
    }
}
