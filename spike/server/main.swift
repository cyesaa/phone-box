// PhoneBox spike server: one TCP port serves the test page over HTTP and a WebSocket at /ws.
// It prints a QR code for http://<LocalHostName>.local:<port>/#k=spike, logs everything the page
// reports, and sends a "tick" to every page once a second (standing in for real snapshots).
//
// Usage: PhoneBoxSpike [--port 4747] [--web <dir>]   (default web dir: Contents/Resources/web in the .app)
import CoreImage
import CryptoKit
import Foundation
import Network
import SystemConfiguration

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    print("\(formatter.string(from: Date())) \(message)")
}

// MARK: Options

var port: UInt16 = 4747
var webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web")
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--port": port = UInt16(arguments.next() ?? "") ?? port
    case "--web": webDirectory = URL(fileURLWithPath: arguments.next() ?? ".")
    default: log("unknown option \(argument)")
    }
}

// MARK: QR code in the terminal (ANSI background colours work on light and dark terminals)

func printQRCode(_ text: String) {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    let image = filter.outputImage!
    let width = Int(image.extent.width), height = Int(image.extent.height)
    var pixels = [UInt8](repeating: 255, count: width * height)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.draw(CIContext().createCGImage(image, from: image.extent)!, in: CGRect(x: 0, y: 0, width: width, height: height))
    let white = "\u{1B}[47m  ", black = "\u{1B}[40m  ", reset = "\u{1B}[0m"
    let quiet = String(repeating: white, count: width + 4) + reset
    print(quiet); print(quiet)
    for y in 0..<height {
        var row = white + white
        for x in 0..<width { row += pixels[y * width + x] < 128 ? black : white }
        print(row + white + white + reset)
    }
    print(quiet); print(quiet)
}

// MARK: HTTP

let contentTypes = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
                    "css": "text/css; charset=utf-8", "mp4": "video/mp4", "png": "image/png"]

func httpResponse(status: String, contentType: String, body: Data, extraHeaders: String = "") -> Data {
    var head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
    head += "Accept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n\(extraHeaders)\r\n"
    return Data(head.utf8) + body
}

/// iOS Safari plays <video> only from servers that answer byte-range requests with 206 Partial Content.
func serveFile(path: String, range: String?) -> Data {
    let name = path == "/" ? "index.html" : String(path.dropFirst())
    guard !name.contains(".."), !name.contains("/"),
          let body = try? Data(contentsOf: webDirectory.appendingPathComponent(name))
    else { return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8)) }
    let type = contentTypes[(name as NSString).pathExtension] ?? "application/octet-stream"
    if let range, range.hasPrefix("bytes="), !body.isEmpty {
        let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        let start = Int(bounds.first ?? "") ?? 0
        let end = min(bounds.count > 1 ? Int(bounds[1]) ?? body.count - 1 : body.count - 1, body.count - 1)
        guard start <= end else {
            return httpResponse(status: "416 Range Not Satisfiable", contentType: "text/plain", body: Data(),
                                extraHeaders: "Content-Range: bytes */\(body.count)\r\n")
        }
        return httpResponse(status: "206 Partial Content", contentType: type, body: body.subdata(in: start..<(end + 1)),
                            extraHeaders: "Content-Range: bytes \(start)-\(end)/\(body.count)\r\n")
    }
    return httpResponse(status: "200 OK", contentType: type, body: body)
}

// MARK: WebSocket (RFC 6455, text frames only; client frames are always masked)

final class Client {
    let id: Int
    let connection: NWConnection
    var isWebSocket = false
    init(id: Int, connection: NWConnection) { self.id = id; self.connection = connection }

    func sendText(_ text: String) {
        let payload = Data(text.utf8)
        var frame = Data([0x81])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65_536 {
            frame.append(126)
            frame.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 0xff)])
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((payload.count >> shift) & 0xff)) }
        }
        connection.send(content: frame + payload, completion: .contentProcessed { _ in })
    }
}

let queue = DispatchQueue(label: "server")
var clients: [Int: Client] = [:]
var nextClientID = 1

func receive(_ client: Client, exactly count: Int, _ handler: @escaping (Data) -> Void) {
    client.connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
        guard let data, data.count == count, error == nil else { return close(client, reason: "read ended") }
        handler(data)
    }
}

func readFrame(_ client: Client) {
    receive(client, exactly: 2) { header in
        let opcode = header[0] & 0x0f
        let masked = header[1] & 0x80 != 0
        let shortLength = Int(header[1] & 0x7f)
        func withLength(_ length: Int) {
            receive(client, exactly: (masked ? 4 : 0) + length) { rest in
                var payload = [UInt8](rest.dropFirst(masked ? 4 : 0))
                if masked {
                    let mask = [UInt8](rest.prefix(4))
                    for i in payload.indices { payload[i] ^= mask[i % 4] }
                }
                handleFrame(client, opcode: opcode, payload: Data(payload))
            }
        }
        if shortLength == 126 {
            receive(client, exactly: 2) { bytes in withLength(Int(bytes[0]) << 8 | Int(bytes[1])) }
        } else if shortLength == 127 {
            receive(client, exactly: 8) { bytes in withLength(bytes.reduce(0) { $0 << 8 | Int($1) }) }
        } else {
            withLength(shortLength)
        }
    }
}

func handleFrame(_ client: Client, opcode: UInt8, payload: Data) {
    switch opcode {
    case 0x1:
        let text = String(decoding: payload, as: UTF8.self)
        if let message = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           message["type"] as? String == "log" {
            log("#\(client.id) page: \(message["msg"] ?? "")")
        } else {
            log("#\(client.id) text: \(text)")
        }
        readFrame(client)
    case 0x8:
        client.connection.send(content: Data([0x88, 0x00]), completion: .contentProcessed { _ in })
        close(client, reason: "close frame")
    case 0x9:
        client.connection.send(content: Data([0x8A, UInt8(payload.count)]) + payload, completion: .contentProcessed { _ in })
        readFrame(client)
    default:
        readFrame(client)
    }
}

func close(_ client: Client, reason: String) {
    guard clients.removeValue(forKey: client.id) != nil else { return }
    if client.isWebSocket { log("#\(client.id) WebSocket closed (\(reason)); open: \(clients.values.filter(\.isWebSocket).count)") }
    client.connection.cancel()
}

func readRequest(_ client: Client, buffer: Data = Data()) {
    client.connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
        guard let data, error == nil else { return close(client, reason: "no request") }
        let request = buffer + data
        guard let end = request.range(of: Data("\r\n\r\n".utf8)) else {
            return request.count > 65_536 ? close(client, reason: "header too big") : readRequest(client, buffer: request)
        }
        let lines = String(decoding: request[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return close(client, reason: "bad request line") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let path = String(parts[1])
        if path == "/ws", headers["upgrade"]?.lowercased() == "websocket", let key = headers["sec-websocket-key"] {
            let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
            let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            client.connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
            client.isWebSocket = true
            log("#\(client.id) WebSocket open from \(headers["user-agent"]?.prefix(60) ?? "?"); open: \(clients.values.filter(\.isWebSocket).count)")
            client.sendText(#"{"type":"hello","nonce":"\#(UUID().uuidString)"}"#)
            readFrame(client)
        } else {
            log("#\(client.id) GET \(path)\(headers["range"].map { " (\($0))" } ?? "")")
            client.connection.send(content: serveFile(path: path, range: headers["range"]),
                                   completion: .contentProcessed { _ in close(client, reason: "http done") })
        }
    }
}

// MARK: Start

let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
listener.stateUpdateHandler = { state in
    switch state {
    case .ready:
        let host = (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? "localhost"
        let url = "http://\(host).local:\(port)/#k=spike"
        log("listening on port \(port), serving \(webDirectory.path)")
        log("open on the iPhone: \(url)")
        printQRCode(url)
    case .failed(let error):
        log("listener failed: \(error)")
        exit(1)
    default:
        break
    }
}
listener.newConnectionHandler = { connection in
    let client = Client(id: nextClientID, connection: connection)
    nextClientID += 1
    clients[client.id] = client
    connection.start(queue: queue)
    readRequest(client)
}
listener.start(queue: queue)

var tick = 0
let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now() + 1, repeating: 1)
timer.setEventHandler {
    tick += 1
    for client in clients.values where client.isWebSocket {
        client.sendText(#"{"type":"tick","n":\#(tick)}"#)
    }
}
timer.resume()
dispatchMain()
