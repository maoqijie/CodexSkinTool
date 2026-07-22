import CodexSkinCore
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Options {
    let port: Int
    let imageURL: URL
    let opacity: Double
    let blur: Double
    let fit: BackgroundFit
    let brightness: Double
    let focusX: Double
    let focusY: Double
    let surface: String
    let ink: String
    let readyURL: URL
    let leaseURL: URL
    let leaseToken: String

    init(arguments: [String]) throws {
        func value(_ flag: String) throws -> String {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                throw InjectorError.invalidArgument("缺少参数 \(flag)")
            }
            return arguments[index + 1]
        }
        guard arguments.contains("--watch"),
              let port = Int(try value("--port")), (1_024...65_535).contains(port),
              let opacity = Double(try value("--opacity")), (0.08...0.85).contains(opacity),
              let blur = Double(try value("--blur")), (0...24).contains(blur),
              let brightness = Double(try value("--brightness")), (0.45...1.25).contains(brightness),
              let focusX = Double(try value("--focus-x")), (0...1).contains(focusX),
              let focusY = Double(try value("--focus-y")), (0...1).contains(focusY),
              let fit = BackgroundFit(rawValue: try value("--fit")) else {
            throw InjectorError.invalidArgument("参数值无效")
        }
        let surface = try value("--surface")
        let ink = try value("--ink")
        guard surface.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
              ink.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw InjectorError.invalidArgument("颜色值无效")
        }
        self.port = port
        imageURL = URL(fileURLWithPath: try value("--image"))
        self.opacity = opacity
        self.blur = blur
        self.fit = fit
        self.brightness = brightness
        self.focusX = focusX
        self.focusY = focusY
        self.surface = surface
        self.ink = ink
        readyURL = URL(fileURLWithPath: try value("--ready-file"))
        leaseURL = URL(fileURLWithPath: try value("--lease-file"))
        leaseToken = try value("--lease-token")
        guard leaseToken.range(of: "^[A-Fa-f0-9-]{36}$", options: .regularExpression) != nil else {
            throw InjectorError.invalidArgument("租约标识无效")
        }
    }
}

private enum InjectorError: LocalizedError {
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

private struct CDPTarget: Decodable {
    let id: String
    let type: String
    let url: String
    let webSocketDebuggerUrl: String
}

private actor CDPSession {
    private let task: URLSessionWebSocketTask
    private var nextID = 1

    init(url: URL) {
        task = URLSession(configuration: .ephemeral).webSocketTask(with: url)
        task.resume()
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
        try await task.send(.data(data))
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
    }
}

private struct Injector {
    let options: Options
    private let session = URLSession(configuration: .ephemeral)

    func run() async throws {
        try await waitForLease()
        let image = try Data(contentsOf: options.imageURL, options: [.mappedIfSafe])
        try validateImage(image)
        let mime = mimeType(for: options.imageURL.pathExtension)
        let dataURL = "data:\(mime);base64,\(image.base64EncodedString())"
        let expression = try injectionExpression(dataURL: dataURL)
        var markedReady = false

        while !Task.isCancelled {
            guard leaseIsValid() else { return }
            do {
                let targets = try await listTargets()
                for target in targets {
                    let socketURL = try validatedSocketURL(target)
                    let cdp = CDPSession(url: socketURL)
                    defer { Task { await cdp.close() } }
                    let probe = try await cdp.evaluate(probeExpression) as? [String: Any]
                    guard probe?["codex"] as? Bool == true else { continue }
                    let installed = try await cdp.evaluate(expression) as? Bool
                    guard installed == true else { continue }
                    let verified = try await cdp.evaluate(try verificationExpression()) as? Bool
                    guard verified == true else { continue }
                    if !markedReady {
                        try Data("{\"status\":\"ready\"}\n".utf8).write(to: options.readyURL, options: .atomic)
                        guard chmod(options.readyURL.path, S_IRUSR | S_IWUSR) == 0 else {
                            throw InjectorError.protocolFailure("无法限制验证文件权限")
                        }
                        markedReady = true
                    }
                }
            } catch {
                fputs("CodexSkinInjector: \(error.localizedDescription)\n", stderr)
            }
            try await Task.sleep(for: .seconds(markedReady ? 2 : 0.35))
        }
    }

    private func waitForLease() async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if leaseIsValid() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw InjectorError.protocolFailure("父进程未建立有效租约")
    }

    private func leaseIsValid() -> Bool {
        guard let data = try? Data(contentsOf: options.leaseURL), data.count <= 64 else { return false }
        return String(decoding: data, as: UTF8.self) == options.leaseToken
    }

    private func validateImage(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 16 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width >= 320, height >= 240, width * height <= 40_000_000,
              CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) != nil else {
            throw InjectorError.invalidArgument("背景 PNG 未通过完整解码与尺寸校验")
        }
    }

    private func listTargets() async throws -> [CDPTarget] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(options.port)/json/list")!)
        request.timeoutInterval = 2
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InjectorError.noCodexTarget }
        return try JSONDecoder().decode([CDPTarget].self, from: data).filter {
            $0.type == "page" && $0.url.hasPrefix("app://")
        }
    }

    private func validatedSocketURL(_ target: CDPTarget) throws -> URL {
        guard target.id.range(of: "^[A-Za-z0-9._-]{1,200}$", options: .regularExpression) != nil,
              let url = URL(string: target.webSocketDebuggerUrl),
              url.scheme == "ws", ["127.0.0.1", "localhost", "::1"].contains(url.host),
              url.port == options.port, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path == "/devtools/page/\(target.id)" else {
            throw InjectorError.invalidEndpoint
        }
        return url
    }

    private var probeExpression: String {
        """
        (() => ({ codex: Boolean(
          document.querySelector('main.main-surface, main.browser-main-surface') &&
          document.querySelector('.app-shell-left-panel, aside') &&
          document.querySelector('[role="main"]')
        ) }))()
        """
    }

    private func verificationExpression() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "opacity": options.opacity,
            "brightness": options.brightness,
            "focusX": options.focusX,
            "focusY": options.focusY,
        ])
        let json = String(decoding: data, as: UTF8.self)
        return """
        (() => {
          const cfg = \(json);
          const layer = document.getElementById('codex-skin-tool-background');
          const style = document.getElementById('codex-skin-tool-style');
          if (!layer || !style || document.documentElement.dataset.codexSkinTool !== 'background-v2') return false;
          const computed = getComputedStyle(layer);
          return computed.backgroundImage !== 'none' && computed.pointerEvents === 'none' &&
            Math.abs(Number(computed.opacity) - cfg.opacity) < 0.001 &&
            computed.filter.includes(`brightness(${cfg.brightness})`) &&
            computed.backgroundPosition === `${cfg.focusX * 100}% ${cfg.focusY * 100}%`;
        })()
        """
    }

    private func injectionExpression(dataURL: String) throws -> String {
        let values: [String: Any] = [
            "image": dataURL,
            "opacity": options.opacity,
            "blur": options.blur,
            "fit": options.fit.rawValue,
            "brightness": options.brightness,
            "focusX": options.focusX,
            "focusY": options.focusY,
            "surface": options.surface,
            "ink": options.ink,
        ]
        let data = try JSONSerialization.data(withJSONObject: values)
        let json = String(decoding: data, as: UTF8.self)
        return """
        (() => {
          const cfg = \(json);
          if (document.getElementById('codex-skin-tool-style') &&
              document.getElementById('codex-skin-tool-background')) return true;
          document.getElementById('codex-skin-tool-style')?.remove();
          document.getElementById('codex-skin-tool-background')?.remove();
          const style = document.createElement('style');
          style.id = 'codex-skin-tool-style';
          style.textContent = `
            #codex-skin-tool-background {
              position: fixed; inset: 0; z-index: 0; pointer-events: none;
              background: ${cfg.focusX * 100}% ${cfg.focusY * 100}% / ${cfg.fit} no-repeat url("${cfg.image}");
              opacity: ${cfg.opacity}; filter: brightness(${cfg.brightness}) blur(${cfg.blur}px);
              transform: scale(${cfg.blur > 0 ? 1.04 : 1});
            }
            #root, body > [data-radix-portal] { position: relative; z-index: 1; }
            body, .main-surface, .browser-main-surface { background-color: transparent !important; }
            .app-shell-left-panel { background-color: color-mix(in srgb, ${cfg.surface} 86%, transparent) !important; }
            main.main-surface, main.browser-main-surface { color: ${cfg.ink}; }
          `;
          const layer = document.createElement('div');
          layer.id = 'codex-skin-tool-background';
          layer.setAttribute('aria-hidden', 'true');
          document.head.append(style);
          document.body.prepend(layer);
          document.documentElement.dataset.codexSkinTool = 'background-v2';
          return true;
        })()
        """
    }

    private func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "heic": "image/heic"
        case "tif", "tiff": "image/tiff"
        case "webp": "image/webp"
        default: "image/png"
        }
    }
}

do {
    let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
    try await Injector(options: options).run()
} catch {
    fputs("CodexSkinInjector: \(error.localizedDescription)\n", stderr)
    exit(1)
}
