import AppKit
import Foundation

public struct CodexAppStatus: Codable, Equatable, Sendable {
    public let isInstalled: Bool
    public let appURL: URL?
    public let version: String?
    public let isRunning: Bool

    public init(isInstalled: Bool, appURL: URL?, version: String?, isRunning: Bool) {
        self.isInstalled = isInstalled
        self.appURL = appURL
        self.version = version
        self.isRunning = isRunning
    }
}

@MainActor
public final class CodexAppService {
    nonisolated public static let bundleIdentifier = "com.openai.codex"
    nonisolated public static let officialTeamIdentifier = "2DC432GLL2"

    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let bundleIdentifier: String
    private let candidateURLs: [URL]

    public init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default,
        bundleIdentifier: String = CodexAppService.bundleIdentifier,
        candidateURLs: [URL]? = nil
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.bundleIdentifier = bundleIdentifier
        let home = fileManager.homeDirectoryForCurrentUser
        self.candidateURLs = candidateURLs ?? [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            home.appendingPathComponent("Applications/Codex.app"),
            home.appendingPathComponent("Applications/ChatGPT.app")
        ]
    }

    public func status() -> CodexAppStatus {
        let appURL = resolveApplicationURL()
        let version = appURL
            .flatMap(Bundle.init(url:))?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return CodexAppStatus(
            isInstalled: appURL != nil,
            appURL: appURL,
            version: version,
            isRunning: !runningApplications().isEmpty
        )
    }

    public func restart(timeout: TimeInterval = 10) async throws {
        guard resolveApplicationURL() != nil else { throw ThemeServiceError.appNotInstalled }
        try await terminate(timeout: timeout)
        try launch()
    }

    public func terminate(timeout: TimeInterval = 10) async throws {
        let applications = runningApplications()
        for application in applications {
            _ = application.terminate()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !runningApplications().isEmpty {
            guard Date() < deadline else {
                throw ThemeServiceError.restartFailed("等待 Codex 优雅退出超时，未强制结束进程")
            }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    public func open() throws {
        guard resolveApplicationURL() != nil else { throw ThemeServiceError.appNotInstalled }
        try launch()
    }

    public func open(remoteDebuggingPort: Int) throws {
        guard let applicationURL = resolveApplicationURL() else { throw ThemeServiceError.appNotInstalled }
        try validateOfficialSignature(at: applicationURL)
        guard (1_024...65_535).contains(remoteDebuggingPort) else {
            throw ThemeServiceError.backgroundSession("调试端口无效")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-na", applicationURL.path, "--args",
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=\(remoteDebuggingPort)",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ThemeServiceError.restartFailed("无法以图片皮肤模式打开 Codex：\(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            throw ThemeServiceError.restartFailed("系统未能以图片皮肤模式打开 Codex")
        }
    }

    public func validateOfficialInstallation() throws {
        guard let applicationURL = resolveApplicationURL() else { throw ThemeServiceError.appNotInstalled }
        try validateOfficialSignature(at: applicationURL)
    }

    public func runningProcessIdentifiers() -> Set<Int32> {
        Set(runningApplications().map(\.processIdentifier))
    }

    private func validateOfficialSignature(at applicationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--verify", "--deep", "--strict",
            "-R=anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(Self.officialTeamIdentifier)\"",
            applicationURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ThemeServiceError.backgroundSession("无法验证 Codex 官方签名")
        }
        guard process.terminationStatus == 0 else {
            throw ThemeServiceError.backgroundSession("Codex 签名或发行者不是预期的 OpenAI 官方应用")
        }
    }

    private func resolveApplicationURL() -> URL? {
        if let workspaceURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier),
           bundleID(at: workspaceURL) == bundleIdentifier {
            return workspaceURL
        }
        return candidateURLs.first {
            fileManager.fileExists(atPath: $0.path) && bundleID(at: $0) == bundleIdentifier
        }
    }

    private func runningApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    private func bundleID(at url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    private func launch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ThemeServiceError.restartFailed("无法打开 Codex：\(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            throw ThemeServiceError.restartFailed("系统未能打开 Codex")
        }
    }
}
