import AppKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum BackgroundFit: String, Codable, CaseIterable, Sendable {
    case cover
    case contain

    public var title: String {
        switch self {
        case .cover: "填充"
        case .contain: "完整显示"
        }
    }
}

public struct CustomThemeDraft: Codable, Equatable, Sendable {
    public var name: String
    public var mode: ThemeMode
    public var codeThemeID: String
    public var accent: String
    public var ink: String
    public var surface: String
    public var contrast: Int
    public var backgroundImageName: String?
    public var backgroundOpacity: Double
    public var backgroundBlur: Double
    public var backgroundFit: BackgroundFit

    public init(
        name: String = "我的主题",
        mode: ThemeMode = .dark,
        codeThemeID: String = "codex",
        accent: String = "#10A37F",
        ink: String = "#F4F4F4",
        surface: String = "#171717",
        contrast: Int = 55,
        backgroundImageName: String? = nil,
        backgroundOpacity: Double = 0.28,
        backgroundBlur: Double = 0,
        backgroundFit: BackgroundFit = .cover
    ) {
        self.name = name
        self.mode = mode
        self.codeThemeID = codeThemeID
        self.accent = accent
        self.ink = ink
        self.surface = surface
        self.contrast = contrast
        self.backgroundImageName = backgroundImageName
        self.backgroundOpacity = backgroundOpacity
        self.backgroundBlur = backgroundBlur
        self.backgroundFit = backgroundFit
    }

    public var theme: Theme {
        Theme(
            id: "custom",
            name: validatedName,
            description: backgroundImageName == nil ? "自定义配色与代码主题" : "自定义配色与本地图片背景",
            mode: mode,
            codeThemeId: ThemeCatalog.supportedCodeThemeIDs.contains(codeThemeID) ? codeThemeID : "codex",
            chromeTheme: ChromeTheme(
                accent: Self.validColor(accent, fallback: "#10A37F"),
                ink: Self.validColor(ink, fallback: mode == .dark ? "#F4F4F4" : "#202020"),
                surface: Self.validColor(surface, fallback: mode == .dark ? "#171717" : "#FFFFFF"),
                contrast: min(100, max(0, contrast)),
                fonts: ThemeFonts(
                    code: "\"SFMono-Regular\", Menlo, monospace",
                    ui: "-apple-system, BlinkMacSystemFont, sans-serif"
                ),
                opaqueWindows: true,
                semanticColors: ThemeSemanticColors(
                    diffAdded: "#32B47A",
                    diffRemoved: "#E5484D",
                    skill: Self.validColor(accent, fallback: "#10A37F")
                )
            )
        )
    }

    public var skinSettings: BackgroundSkinSettings? {
        guard let backgroundImageName else { return nil }
        return BackgroundSkinSettings(
            imageName: backgroundImageName,
            opacity: min(0.85, max(0.08, backgroundOpacity)),
            blur: min(24, max(0, backgroundBlur)),
            fit: backgroundFit
        )
    }

    private var validatedName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "我的主题" : String(value.prefix(40))
    }

    private static func validColor(_ value: String, fallback: String) -> String {
        value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil
            ? fallback
            : value.uppercased()
    }
}

public struct BackgroundSkinSettings: Codable, Equatable, Sendable {
    public let imageName: String
    public let opacity: Double
    public let blur: Double
    public let fit: BackgroundFit

    public init(imageName: String, opacity: Double, blur: Double, fit: BackgroundFit) {
        self.imageName = imageName
        self.opacity = opacity
        self.blur = blur
        self.fit = fit
    }
}

public struct CustomThemeStore {
    public let supportDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        supportDirectoryURL: URL = ConfigurationPaths.live.supportDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.supportDirectoryURL = supportDirectoryURL
        self.fileManager = fileManager
    }

    public var draftURL: URL { supportDirectoryURL.appendingPathComponent("custom-theme.json") }
    public var backgroundDirectoryURL: URL { supportDirectoryURL.appendingPathComponent("Backgrounds") }

    public func load() throws -> CustomThemeDraft {
        guard fileManager.fileExists(atPath: draftURL.path) else { return CustomThemeDraft() }
        do {
            return try JSONDecoder().decode(CustomThemeDraft.self, from: Data(contentsOf: draftURL))
        } catch {
            throw ThemeServiceError.invalidState("自定义主题文件无法读取")
        }
    }

    public func save(_ draft: CustomThemeDraft) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try secureWrite(encoder.encode(draft), to: draftURL)
    }

    public func importBackground(from sourceURL: URL) throws -> String {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ThemeServiceError.invalidBackground("请选择普通图片文件")
        }
        guard let size = values.fileSize, size > 0, size <= 16 * 1_024 * 1_024 else {
            throw ThemeServiceError.invalidBackground("图片大小必须在 16 MB 以内")
        }
        let data = try limitedData(from: sourceURL, maximumBytes: 16 * 1_024 * 1_024)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width >= 320, height >= 240, width <= 16_384, height <= 16_384,
              width * height <= 40_000_000,
              CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) != nil else {
            throw ThemeServiceError.invalidBackground("图片必须是可完整解码的单帧图片，尺寸至少 320x240 且像素总量不超过 4000 万")
        }
        let allowed: [UTType] = [.png, .jpeg, .heic, .tiff, .webP]
        guard let imageType = UTType(type as String), allowed.contains(where: { imageType.conforms(to: $0) }) else {
            throw ThemeServiceError.invalidBackground("仅支持 PNG、JPEG、HEIC、TIFF 或 WebP 图片")
        }

        let normalized = NSMutableData()
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithData(normalized, UTType.png.identifier as CFString, 1, nil) else {
            throw ThemeServiceError.invalidBackground("无法规范化背景图片")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), normalized.length <= 16 * 1_024 * 1_024 else {
            throw ThemeServiceError.invalidBackground("规范化后的 PNG 图片超过 16 MB")
        }
        let fileName = "background-\(UUID().uuidString).png"
        try fileManager.createDirectory(at: backgroundDirectoryURL, withIntermediateDirectories: true)
        try secureWrite(normalized as Data, to: backgroundDirectoryURL.appendingPathComponent(fileName))
        return fileName
    }

    public func backgroundURL(named name: String?) -> URL? {
        guard let name, URL(fileURLWithPath: name).lastPathComponent == name else { return nil }
        let url = backgroundDirectoryURL.appendingPathComponent(name).standardizedFileURL
        guard url.deletingLastPathComponent() == backgroundDirectoryURL.standardizedFileURL else { return nil }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return url
    }

    public func removeBackground(named name: String?) throws {
        guard let url = backgroundURL(named: name) else { return }
        try fileManager.removeItem(at: url)
    }

    private func secureWrite(_ data: Data, to destination: URL) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard chmod(temporary.path, S_IRUSR | S_IWUSR) == 0,
                  rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ThemeServiceError.fileOperation("写入自定义主题失败：\(error.localizedDescription)")
        }
    }

    private func limitedData(from url: URL, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw ThemeServiceError.invalidBackground("图片大小必须在 16 MB 以内")
        }
        return data
    }
}
