import Foundation

/// The request line and headers of one HTTP/1.1 request.
public struct HTTPRequestHead: Equatable, Sendable {
    public var method: String
    /// Without the query string.
    public var path: String
    /// Header names lowercased.
    public var headers: [String: String]

    public init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headers = headers
    }
}

public enum HTTPRequestParser {
    public static let maxHeadBytes = 16_384

    public enum Result: Equatable, Sendable {
        case incomplete
        /// The first byte is a TLS handshake record (0x16): the browser tried HTTPS. Close at once so it
        /// falls back to http:// (spike: Safari tries HTTPS for an address typed without a scheme).
        case tls
        case invalid
        case complete(HTTPRequestHead)
    }

    public static func parse(_ data: Data) -> Result {
        if data.first == 0x16 { return .tls }
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeadBytes ? .invalid : .incomplete
        }
        let lines = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let target = String(parts[1])
        let path = target.firstIndex(of: "?").map { String(target[..<$0]) } ?? target
        return .complete(HTTPRequestHead(method: String(parts[0]), path: path, headers: headers))
    }
}

/// `Range: bytes=…` for the keep-awake video: iOS plays a <video> only from a server that answers byte
/// ranges with 206 (spike).
public enum ByteRange {
    public enum Result: Equatable, Sendable {
        case full
        case partial(ClosedRange<Int>)
        case unsatisfiable
    }

    /// Handles `bytes=a-b`, `bytes=a-` and `bytes=-n`. Anything else, including several ranges, gets the
    /// whole body, which HTTP allows.
    public static func resolve(header: String?, length: Int) -> Result {
        guard let header, header.hasPrefix("bytes="), length > 0 else { return .full }
        let spec = header.dropFirst(6)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .full }
        let startText = spec[..<dash]
        let endText = spec[spec.index(after: dash)...]
        if startText.isEmpty {
            guard let suffix = Int(endText), suffix > 0 else { return .unsatisfiable }
            return .partial(max(0, length - suffix)...(length - 1))
        }
        guard let start = Int(startText), start >= 0 else { return .full }
        guard start < length else { return .unsatisfiable }
        let end = endText.isEmpty ? length - 1 : min(Int(endText) ?? length - 1, length - 1)
        guard end >= start else { return .unsatisfiable }
        return .partial(start...end)
    }
}

public enum HTTPResponse {
    public static let contentTypes = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8", "mp4": "video/mp4", "png": "image/png", "json": "application/json",
    ]

    public static func make(status: String, contentType: String, body: Data, extraHeaders: [String] = []) -> Data {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        head += "Accept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n"
        for header in extraHeaders { head += header + "\r\n" }
        return Data((head + "\r\n").utf8) + body
    }

    /// A file's response for a GET with an optional Range header.
    public static func file(_ body: Data, name: String, range: String?) -> Data {
        let type = contentTypes[(name as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
        switch ByteRange.resolve(header: range, length: body.count) {
        case .full:
            return make(status: "200 OK", contentType: type, body: body)
        case let .partial(bounds):
            return make(status: "206 Partial Content", contentType: type,
                        body: body.subdata(in: bounds.lowerBound..<(bounds.upperBound + 1)),
                        extraHeaders: ["Content-Range: bytes \(bounds.lowerBound)-\(bounds.upperBound)/\(body.count)"])
        case .unsatisfiable:
            return make(status: "416 Range Not Satisfiable", contentType: "text/plain", body: Data(),
                        extraHeaders: ["Content-Range: bytes */\(body.count)"])
        }
    }

    public static let notFound = make(status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8))
    public static let badRequest = make(status: "400 Bad Request", contentType: "text/plain", body: Data("bad request".utf8))
    public static let busy = make(status: "503 Service Unavailable", contentType: "text/plain", body: Data("too many phones".utf8))
}
