import Foundation

enum InjectorError: LocalizedError {
    case invalidArgument(String)
    case invalidEndpoint
    case noCodexTarget
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): message
        case .invalidEndpoint: "CDP 端点不是受信任的本机 Codex 页面"
        case .noCodexTarget: "未找到 Codex 渲染页面"
        case .protocolFailure(let message): "CDP 协议错误：\(message)"
        }
    }
}

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private enum State { case pending, opened, failed(String) }
    private let lock = NSLock()
    private var state = State.pending

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        update(.opened)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        update(.failed(error.localizedDescription), onlyIfPending: true)
    }

    func waitUntilOpen(timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch snapshot() {
            case .pending: try await Task.sleep(for: .milliseconds(25))
            case .opened: return
            case .failed(let message):
                throw InjectorError.protocolFailure("WebSocket 握手失败：\(message)")
            }
        }
        throw InjectorError.protocolFailure("WebSocket 握手超时")
    }

    private func snapshot() -> State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    private func update(_ newState: State, onlyIfPending: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        if !onlyIfPending || isPending { state = newState }
    }

    private var isPending: Bool {
        if case .pending = state { return true }
        return false
    }
}

actor CDPSession {
    private let delegate: WebSocketDelegate
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    private var nextID = 1

    init(url: URL) async throws {
        let delegate = WebSocketDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        self.delegate = delegate
        self.session = session
        task = session.webSocketTask(with: url)
        task.resume()
        try await delegate.waitUntilOpen()
    }

    func evaluate(_ expression: String) async throws -> Any? {
        let id = nextID
        nextID += 1
        let payload: [String: Any] = [
            "id": id,
            "method": "Runtime.evaluate",
            "params": ["expression": expression, "awaitPromise": true, "returnByValue": true],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw InjectorError.protocolFailure("无法编码 CDP 请求")
        }
        try await task.send(.string(json))
        while true {
            let message = try await task.receive()
            let responseData: Data
            switch message {
            case .data(let data): responseData = data
            case .string(let string): responseData = Data(string.utf8)
            @unknown default: continue
            }
            guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  response["id"] as? Int == id else { continue }
            if let error = response["error"] as? [String: Any] {
                throw InjectorError.protocolFailure(error["message"] as? String ?? "未知响应")
            }
            guard let result = response["result"] as? [String: Any],
                  let remote = result["result"] as? [String: Any] else { return nil }
            if result["exceptionDetails"] != nil {
                throw InjectorError.protocolFailure("渲染器拒绝执行")
            }
            return remote["value"]
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}
