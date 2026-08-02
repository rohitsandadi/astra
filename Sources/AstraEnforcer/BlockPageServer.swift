import AstraCore
import Foundation
@preconcurrency import Network

enum BlockPageServerError: Error, Equatable {
    case failedToStart(String)
    case timedOut
}

enum BlockPageRenderer {
    static func render(session: FocusSession) -> String {
        let intention = session.intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeIntention = intention.flatMap { $0.isEmpty ? nil : escapeHTML($0) }
        let endMilliseconds = Int(session.endDate.timeIntervalSince1970 * 1_000)
        let intentionMarkup = safeIntention.map { "<p class=\"intention\">\($0)</p>" } ?? ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
          <title>Astra — Focus in progress</title>
          <style>
            :root { color-scheme: light dark; --accent: #6669B7; }
            * { box-sizing: border-box; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 32px;
              color: CanvasText; background: Canvas; font: 15px -apple-system, BlinkMacSystemFont, sans-serif; }
            main { width: min(520px, 100%); text-align: center; padding: 42px; border-radius: 28px;
              border: 1px solid color-mix(in srgb, CanvasText 12%, transparent);
              background: color-mix(in srgb, Canvas 92%, var(--accent) 8%); }
            .mark { width: 44px; height: 44px; margin: 0 auto 24px; border: 2px solid var(--accent);
              border-radius: 50%; box-shadow: 0 0 32px color-mix(in srgb, var(--accent) 24%, transparent); }
            h1 { margin: 0 0 10px; font-size: 28px; letter-spacing: -.025em; }
            p { margin: 0; color: color-mix(in srgb, CanvasText 65%, transparent); line-height: 1.5; }
            .timer { margin: 28px 0 8px; color: var(--accent); font: 600 36px ui-monospace, SFMono-Regular, monospace;
              font-variant-numeric: tabular-nums; }
            .intention { margin-top: 24px; color: CanvasText; }
          </style>
        </head>
        <body><main>
          <div class="mark" aria-hidden="true"></div>
          <h1>This site is resting</h1>
          <p>Astra is protecting the time you set aside.</p>
          <div class="timer" id="timer" aria-live="polite">--:--</div>
          <p id="end"></p>
          \(intentionMarkup)
        </main>
        <script>
          const end = new Date(\(endMilliseconds));
          const timer = document.getElementById('timer');
          document.getElementById('end').textContent = 'Focus ends at ' + end.toLocaleTimeString([], {hour:'numeric', minute:'2-digit'});
          function update() {
            const seconds = Math.max(0, Math.ceil((end - Date.now()) / 1000));
            const h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60), s = seconds % 60;
            timer.textContent = (h ? String(h).padStart(2,'0') + ':' : '') + String(m).padStart(2,'0') + ':' + String(s).padStart(2,'0');
          }
          update(); setInterval(update, 1000);
        </script></body></html>
        """
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

protocol BlockPageServing: Sendable {
    func start(for session: FocusSession) throws -> URL
    func stop()
}

/// Tiny HTTP server that can only be reached through the local loopback interface.
/// It has no routes that mutate state and never makes outbound requests.
final class LoopbackHTTPBlockPageServer: BlockPageServing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.rohitsandadi.astra.block-page")
    private let lock = NSLock()
    private var listener: NWListener?
    private var responseData = Data()

    func start(for session: FocusSession) throws -> URL {
        stop()

        let html = BlockPageRenderer.render(session: session)
        let body = Data(html.utf8)
        lock.withLock { responseData = Self.httpResponse(body: body) }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let loopback = IPv4Address("127.0.0.1") else {
            throw BlockPageServerError.failedToStart("The loopback interface is unavailable.")
        }
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(loopback), port: .any)

        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        let startup = ListenerStartupResult()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let port = listener.port?.rawValue
                let result: Result<UInt16, Error> = port.map { .success($0) }
                    ?? .failure(BlockPageServerError.failedToStart("No loopback port was assigned."))
                if startup.setIfEmpty(result) {
                    ready.signal()
                }
            case .failed(let error):
                if startup.setIfEmpty(.failure(BlockPageServerError.failedToStart(error.localizedDescription))) {
                    ready.signal()
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        lock.lock()
        self.listener = listener
        lock.unlock()
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 2) == .success else {
            stop()
            throw BlockPageServerError.timedOut
        }
        let port = try startup.get()!.get()
        return URL(string: "http://127.0.0.1:\(port)/blocked")!
    }

    func stop() {
        let active = lock.withLock { () -> NWListener? in
            defer { listener = nil }
            return listener
        }
        active?.stateUpdateHandler = nil
        active?.newConnectionHandler = nil
        active?.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] _, _, _, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            let response = self.lock.withLock { self.responseData }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func httpResponse(body: Data) -> Data {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        X-Content-Type-Options: nosniff\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    deinit { stop() }
}

private final class ListenerStartupResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<UInt16, Error>?

    func setIfEmpty(_ newValue: Result<UInt16, Error>) -> Bool {
        lock.withLock {
            guard result == nil else { return false }
            result = newValue
            return true
        }
    }

    func get() -> Result<UInt16, Error>? {
        lock.withLock { result }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
