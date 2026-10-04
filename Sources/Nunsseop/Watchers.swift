import AppKit
import Network

/// Adds new screenshots to the shelf as they are saved.
@MainActor
final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?
    var isEnabled = true

    private var source: DispatchSourceFileSystemObject?
    private var seen: Set<String> = []
    private let startedAt = Date()

    static var directory: URL {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let path = (configured.map { ($0 as NSString).expandingTildeInPath }) ?? ""
        if !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func start() {
        let directory = Self.directory
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scan(directory)
                // The screenshot marker can land a moment after the file appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.scan(directory) }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func scan(_ directory: URL) {
        guard isEnabled else { return }
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        for url in files where !seen.contains(url.path) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let created = values.creationDate, created > startedAt,
                  ["png", "jpg", "jpeg", "heic", "mov"].contains(url.pathExtension.lowercased()),
                  Self.looksLikeScreenshot(url) else { continue }
            seen.insert(url.path)
            onScreenshot?(url)
        }
    }

    /// macOS marks its screenshots with this extended attribute regardless of language.
    private static func looksLikeScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }
}

/// Shows the Caps Lock state whenever it changes.
@MainActor
final class CapsLockWatcher {
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var last = NSEvent.modifierFlags.contains(.capsLock)

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func start() {
        guard timer == nil else { return }
        last = NSEvent.modifierFlags.contains(.capsLock)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = NSEvent.modifierFlags.contains(.capsLock)
                if now != self.last {
                    self.last = now
                    self.onChange?(now)
                }
            }
        }
    }
}

/// Accepts notifications from local tools such as Claude Code hooks:
/// `POST http://127.0.0.1:47750/notify` with `Authorization: Bearer <token>` and a JSON body
/// `{"title": "...", "message": "..."}`. The token lives in Application Support/Nunsseop/notify-token.
final class NotifyServer: @unchecked Sendable {
    static let port: UInt16 = 47750
    var onNotify: (@MainActor (String, String?) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "nunsseop.notify")
    /// Touched only on `queue`.
    private var openConnections = 0
    private static let maxConnections = 8
    private static let maxRequestBytes = 65_536
    let token: String

    /// A shell command for Claude Code's Notification hook. Claude Code passes the event as
    /// JSON on stdin; its `message` field is sent as the notification text.
    static var hookCommand: String {
        "plutil -extract message raw -o - - 2>/dev/null | curl -s -m 2 -X POST http://127.0.0.1:\(port)/notify "
            + "-H \"Authorization: Bearer $(cat \"$HOME/Library/Application Support/Nunsseop/notify-token\")\" "
            + "-H 'X-Title: Claude Code' --data-binary @- >/dev/null || true"
    }

    static var tokenURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nunsseop/notify-token")
    }

    init() {
        let url = Self.tokenURL
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 32 {
            token = existing
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
        }
    }

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        guard openConnections < Self.maxConnections else {
            connection.cancel()
            return
        }
        openConnections += 1
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.openConnections -= 1
            default: break
            }
        }
        connection.start(queue: queue)
        // Drop clients that connect and then stall.
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || buffer.count > Self.maxRequestBytes {
                self.reply(connection, status: "400 Bad Request")
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private static func parse(_ data: Data) -> Request? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), (0...maxRequestBytes).contains(length) else { return nil }
        let body = data[separator.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body.prefix(length)))
    }

    private func respond(to request: Request, on connection: NWConnection) {
        guard request.method == "POST", request.path == "/notify" else {
            return reply(connection, status: "404 Not Found")
        }
        guard Self.constantTimeEqual(request.headers["authorization"] ?? "", "Bearer \(token)") else {
            return reply(connection, status: "401 Unauthorized")
        }
        // The body is either JSON {"title", "message"} or plain text with the title in X-Title.
        let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
        let text = json == nil ? String(data: request.body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let title = String((json?["title"] as? String ?? request.headers["x-title"] ?? "Notification").prefix(80))
        let message = (json?["message"] as? String ?? text).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
        let handler = onNotify
        DispatchQueue.main.async { MainActor.assumeIsolated { handler?(title, message) } }
        reply(connection, status: "204 No Content")
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var difference = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            difference |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return difference == 0
    }

    private func reply(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
