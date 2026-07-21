import Darwin
import Foundation

public struct BackgroundSkinStatus: Codable, Equatable, Sendable {
    public let active: Bool
    public let port: Int?

    public init(active: Bool, port: Int?) {
        self.active = active
        self.port = port
    }

    public static let inactive = BackgroundSkinStatus(active: false, port: nil)
}

private enum SessionPhase: String, Codable { case starting, active }

private struct ProcessIdentity: Codable {
    let pid: Int32
    let startedAt: String
}

private struct BackgroundSessionState: Codable {
    let version: Int
    var phase: SessionPhase
    let port: Int
    let helperPath: String
    let sessionID: String
    var helper: ProcessIdentity?
    var codex: ProcessIdentity?
    let createdAt: Date
}

public struct BackgroundSkinSession {
    private let supportDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        supportDirectoryURL: URL = ConfigurationPaths.live.supportDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.supportDirectoryURL = supportDirectoryURL
        self.fileManager = fileManager
    }

    private var stateURL: URL { supportDirectoryURL.appendingPathComponent("background-session.json") }
    private var readyURL: URL { supportDirectoryURL.appendingPathComponent("background-ready.json") }
    private var logURL: URL { supportDirectoryURL.appendingPathComponent("background-injector.log") }
    private var leaseURL: URL { supportDirectoryURL.appendingPathComponent("background-session.lease") }

    public func status() -> BackgroundSkinStatus {
        guard let state = try? readState(), state.phase == .active,
              let helper = state.helper, processMatches(helper, path: state.helperPath, port: state.port),
              let codex = state.codex, listenerMatches(codex, port: state.port) else {
            return .inactive
        }
        return BackgroundSkinStatus(active: true, port: state.port)
    }

    @MainActor
    public func reconcile(appService: CodexAppService) async throws -> BackgroundSkinStatus {
        let current = status()
        guard !current.active, fileManager.fileExists(atPath: stateURL.path) else { return current }
        let stoppedCodex = try await recoverAndStop(appService: appService)
        if stoppedCodex { try appService.open() }
        return .inactive
    }

    @MainActor
    public func start(
        settings: BackgroundSkinSettings,
        theme: Theme,
        appService: CodexAppService,
        timeout: TimeInterval = 45
    ) async throws {
        guard let imageURL = CustomThemeStore(supportDirectoryURL: supportDirectoryURL)
            .backgroundURL(named: settings.imageName) else {
            throw ThemeServiceError.invalidBackground("已选择的图片不存在，请重新选择")
        }
        _ = try await recoverAndStop(appService: appService)
        try fileManager.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: readyURL)
        let port = try availablePort()
        let helperURL = try resolveHelperURL()
        let sessionID = UUID().uuidString
        try writeState(BackgroundSessionState(
            version: 2,
            phase: .starting,
            port: port,
            helperPath: helperURL.resolvingSymlinksInPath().path,
            sessionID: sessionID,
            helper: nil,
            codex: nil,
            createdAt: Date()
        ))

        var helperProcess: Process?
        do {
            try appService.validateOfficialInstallation()
            try await appService.terminate(timeout: 10)
            try appService.open(remoteDebuggingPort: port)
            let codex = try await waitForCodexListener(port: port, appService: appService, timeout: 15)

            let process = try launchHelper(
                at: helperURL,
                port: port,
                imageURL: imageURL,
                settings: settings,
                theme: theme,
                sessionID: sessionID
            )
            helperProcess = process
            guard let helperStart = processStartTime(process.processIdentifier) else {
                throw ThemeServiceError.backgroundSession("无法记录注入器进程身份")
            }
            var state = try requiredState()
            state.helper = ProcessIdentity(pid: process.processIdentifier, startedAt: helperStart)
            state.codex = codex
            try writeState(state)
            try writeLease(sessionID)

            let deadline = Date().addingTimeInterval(timeout)
            while !fileManager.fileExists(atPath: readyURL.path) {
                guard process.isRunning else {
                    throw ThemeServiceError.backgroundSession("注入器提前退出，请查看 \(logURL.path)")
                }
                guard listenerMatches(codex, port: port) else {
                    throw ThemeServiceError.backgroundSession("Codex 回环调试端口已失效")
                }
                guard Date() < deadline else {
                    throw ThemeServiceError.backgroundSession("等待 Codex 图片层验证超时")
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            guard processMatches(state.helper!, path: state.helperPath, port: port),
                  listenerMatches(codex, port: port) else {
                throw ThemeServiceError.backgroundSession("图片皮肤进程身份验证失败")
            }
            state.phase = .active
            try writeState(state)
        } catch {
            helperProcess?.terminate()
            try? await appService.terminate(timeout: 5)
            clearState()
            throw error
        }
    }

    @MainActor
    public func recoverAndStop(appService: CodexAppService) async throws -> Bool {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            try? fileManager.removeItem(at: readyURL)
            return false
        }
        let state: BackgroundSessionState
        do {
            state = try requiredState()
        } catch {
            let hasListener = hasManagedDebugListener(appService: appService)
            if hasListener {
                try appService.validateOfficialInstallation()
                try await appService.terminate(timeout: 10)
            }
            clearState()
            return hasListener
        }
        if let helper = state.helper, kill(helper.pid, 0) == 0 {
            guard processMatches(helper, path: state.helperPath, port: state.port) else {
                throw ThemeServiceError.backgroundSession("注入器状态与进程身份不一致，已拒绝结束未知进程")
            }
            _ = kill(helper.pid, SIGTERM)
            let deadline = Date().addingTimeInterval(5)
            while processMatches(helper, path: state.helperPath, port: state.port), Date() < deadline {
                usleep(100_000)
            }
            if processMatches(helper, path: state.helperPath, port: state.port) { _ = kill(helper.pid, SIGKILL) }
        }
        let hasRecordedListener = state.codex.map({ listenerMatches($0, port: state.port) }) == true
        let hasUnrecordedListener = state.phase == .starting && hasManagedDebugListener(appService: appService)
        if hasRecordedListener || hasUnrecordedListener {
            try appService.validateOfficialInstallation()
            try await appService.terminate(timeout: 10)
        }
        clearState()
        return hasRecordedListener || hasUnrecordedListener
    }

    private func launchHelper(
        at helperURL: URL,
        port: Int,
        imageURL: URL,
        settings: BackgroundSkinSettings,
        theme: Theme,
        sessionID: String
    ) throws -> Process {
        try? fileManager.removeItem(at: logURL)
        guard fileManager.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ThemeServiceError.fileOperation("无法创建图片注入器日志")
        }
        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            "--watch", "--port", String(port), "--image", imageURL.path,
            "--opacity", String(settings.opacity), "--blur", String(settings.blur),
            "--fit", settings.fit.rawValue, "--surface", theme.chromeTheme.surface,
            "--ink", theme.chromeTheme.ink, "--ready-file", readyURL.path,
            "--lease-file", leaseURL.path, "--lease-token", sessionID,
        ]
        let log = try FileHandle(forWritingTo: logURL)
        process.standardOutput = log
        process.standardError = log
        do {
            try process.run()
            return process
        } catch {
            throw ThemeServiceError.backgroundSession("无法启动本地注入器：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func waitForCodexListener(
        port: Int,
        appService: CodexAppService,
        timeout: TimeInterval
    ) async throws -> ProcessIdentity {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for pid in appService.runningProcessIdentifiers() {
                if let startedAt = processStartTime(pid) {
                    let identity = ProcessIdentity(pid: pid, startedAt: startedAt)
                    if listenerMatches(identity, port: port) { return identity }
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ThemeServiceError.backgroundSession("等待 Codex 回环调试端口超时")
    }

    private func listenerMatches(_ identity: ProcessIdentity, port: Int) -> Bool {
        guard processStartTime(identity.pid) == identity.startedAt else { return false }
        return listenerPIDs(port: port).contains(identity.pid)
    }

    @MainActor
    private func hasManagedDebugListener(appService: CodexAppService) -> Bool {
        let appPIDs = appService.runningProcessIdentifiers()
        return (9_341...9_380).contains { !listenerPIDs(port: $0).isDisjoint(with: appPIDs) }
    }

    private func listenerPIDs(port: Int) -> Set<Int32> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let fields = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Set(fields.split(separator: "\n").compactMap { field in
            field.first == "p" ? Int32(field.dropFirst()) : nil
        })
    }

    private func processMatches(_ identity: ProcessIdentity, path: String, port: Int) -> Bool {
        guard processStartTime(identity.pid) == identity.startedAt else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-p", String(identity.pid), "-o", "command="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let command = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0
            && (command == path || command.hasPrefix(path + " "))
            && command.contains("--port \(port)")
    }

    private func processStartTime(_ pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "lstart="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let value = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !value.isEmpty ? value : nil
    }

    private func resolveHelperURL() throws -> URL {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = executable.deletingLastPathComponent().appendingPathComponent("CodexSkinInjector")
        guard fileManager.isExecutableFile(atPath: sibling.path) else {
            throw ThemeServiceError.backgroundSession("应用包缺少 CodexSkinInjector")
        }
        return sibling
    }

    private func availablePort() throws -> Int {
        for port in 9_341...9_380 where canBind(port: port) { return port }
        throw ThemeServiceError.backgroundSession("本机 9341-9380 端口均不可用")
    }

    private func canBind(port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func readState() throws -> BackgroundSessionState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackgroundSessionState.self, from: Data(contentsOf: stateURL))
    }

    private func requiredState() throws -> BackgroundSessionState {
        guard let state = try readState() else { throw ThemeServiceError.invalidState("图片皮肤会话状态缺失") }
        return state
    }

    private func writeState(_ state: BackgroundSessionState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let temporary = stateURL.deletingLastPathComponent().appendingPathComponent(".session.\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: try encoder.encode(state),
            attributes: [.posixPermissions: 0o600]
        ), rename(temporary.path, stateURL.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw ThemeServiceError.fileOperation("无法保存图片皮肤会话")
        }
    }

    private func writeLease(_ sessionID: String) throws {
        let temporary = leaseURL.deletingLastPathComponent().appendingPathComponent(".lease.\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: Data(sessionID.utf8),
            attributes: [.posixPermissions: 0o600]
        ), rename(temporary.path, leaseURL.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw ThemeServiceError.fileOperation("无法建立图片注入器租约")
        }
    }

    private func clearState() {
        try? fileManager.removeItem(at: stateURL)
        try? fileManager.removeItem(at: readyURL)
        try? fileManager.removeItem(at: leaseURL)
    }
}
