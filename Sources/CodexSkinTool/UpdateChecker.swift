import CodexSkinCore
import Foundation
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle

    let currentVersion: String
    let repositoryURL = URL(string: "https://github.com/maoqijie/CodexSkinTool")!

    private let session: URLSession
    private let latestVersionURL = URL(
        string: "https://raw.githubusercontent.com/maoqijie/CodexSkinTool/main/VERSION"
    )!

    init(bundle: Bundle = .main, session: URLSession = .shared) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0.0.0"
        self.session = session
    }

    func checkForUpdates() async {
        guard state != .checking else { return }
        state = .checking

        do {
            let latestVersion = try await fetchLatestVersion()
            guard let isNewer = Self.isVersion(latestVersion, newerThan: currentVersion) else {
                throw CheckError.invalidVersion
            }

            state = isNewer
                ? .updateAvailable(version: Self.displayVersion(latestVersion), url: repositoryURL)
                : .upToDate
        } catch {
            if Task.isCancelled {
                state = .idle
            } else {
                state = .failed(message: Self.failureMessage(for: error))
            }
        }
    }

    func retry() async {
        await checkForUpdates()
    }

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool? {
        guard let candidate = AppVersion(candidate),
              let current = AppVersion(current) else { return nil }
        return candidate > current
    }

    private func fetchLatestVersion() async throws -> String {
        var request = URLRequest(
            url: latestVersionURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.setValue("CodexSkinTool/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              !data.isEmpty,
              data.count <= 64,
              let version = String(data: data, encoding: .utf8) else {
            throw CheckError.badResponse
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func displayVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { $0 == "v" || $0 == "V" } == true
            ? String(trimmed.dropFirst())
            : trimmed
    }

    nonisolated private static func failureMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "当前无法连接网络，请检查网络后重试。"
            case .timedOut:
                return "检查更新超时，请稍后重试。"
            default:
                return "无法连接更新服务，请稍后重试。"
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "检查更新失败，请稍后重试。"
    }
}

private enum CheckError: LocalizedError {
    case badResponse
    case invalidVersion

    var errorDescription: String? {
        switch self {
        case .badResponse: "更新服务返回异常，请稍后重试。"
        case .invalidVersion: "最新版本号格式无效。"
        }
    }
}
