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
    public var backgroundBrightness: Double
    public var backgroundFocusX: Double
    public var backgroundFocusY: Double

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
        backgroundFit: BackgroundFit = .cover,
        backgroundBrightness: Double = 1.0,
        backgroundFocusX: Double = 0.5,
        backgroundFocusY: Double = 0.5
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
        self.backgroundBrightness = backgroundBrightness
        self.backgroundFocusX = backgroundFocusX
        self.backgroundFocusY = backgroundFocusY
    }

    private enum CodingKeys: String, CodingKey {
        case name, mode, codeThemeID, accent, ink, surface, contrast
        case backgroundImageName, backgroundOpacity, backgroundBlur, backgroundFit
        case backgroundBrightness, backgroundFocusX, backgroundFocusY
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "我的主题"
        mode = try values.decodeIfPresent(ThemeMode.self, forKey: .mode) ?? .dark
        codeThemeID = try values.decodeIfPresent(String.self, forKey: .codeThemeID) ?? "codex"
        accent = try values.decodeIfPresent(String.self, forKey: .accent) ?? "#10A37F"
        ink = try values.decodeIfPresent(String.self, forKey: .ink) ?? "#F4F4F4"
        surface = try values.decodeIfPresent(String.self, forKey: .surface) ?? "#171717"
        contrast = try values.decodeIfPresent(Int.self, forKey: .contrast) ?? 55
        backgroundImageName = try values.decodeIfPresent(String.self, forKey: .backgroundImageName)
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.28
        backgroundBlur = try values.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
        backgroundFit = try values.decodeIfPresent(BackgroundFit.self, forKey: .backgroundFit) ?? .cover
        backgroundBrightness = try values.decodeIfPresent(Double.self, forKey: .backgroundBrightness) ?? 1.0
        backgroundFocusX = try values.decodeIfPresent(Double.self, forKey: .backgroundFocusX) ?? 0.5
        backgroundFocusY = try values.decodeIfPresent(Double.self, forKey: .backgroundFocusY) ?? 0.5
    }

    public var theme: Theme {
        theme(id: "custom")
    }

    public func theme(id: String) -> Theme {
        Theme(
            id: id,
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
            fit: backgroundFit,
            brightness: min(1.25, max(0.45, backgroundBrightness)),
            focusX: min(1, max(0, backgroundFocusX)),
            focusY: min(1, max(0, backgroundFocusY))
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
    public let brightness: Double
    public let focusX: Double
    public let focusY: Double

    public init(
        imageName: String,
        opacity: Double,
        blur: Double,
        fit: BackgroundFit,
        brightness: Double = 1.0,
        focusX: Double = 0.5,
        focusY: Double = 0.5
    ) {
        self.imageName = imageName
        self.opacity = opacity
        self.blur = blur
        self.fit = fit
        self.brightness = brightness
        self.focusX = focusX
        self.focusY = focusY
    }

    private enum CodingKeys: String, CodingKey {
        case imageName, opacity, blur, fit, brightness, focusX, focusY
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        imageName = try values.decode(String.self, forKey: .imageName)
        opacity = try values.decode(Double.self, forKey: .opacity)
        blur = try values.decode(Double.self, forKey: .blur)
        fit = try values.decode(BackgroundFit.self, forKey: .fit)
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? 1.0
        focusX = try values.decodeIfPresent(Double.self, forKey: .focusX) ?? 0.5
        focusY = try values.decodeIfPresent(Double.self, forKey: .focusY) ?? 0.5
    }
}

public struct BackgroundImportResult: Equatable, Sendable {
    public let imageName: String
    public let suggestedAccent: String?

    public init(imageName: String, suggestedAccent: String?) {
        self.imageName = imageName
        self.suggestedAccent = suggestedAccent
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

    public func importBackground(from sourceURL: URL) throws -> BackgroundImportResult {
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
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            throw ThemeServiceError.invalidBackground("图片必须是可完整解码的单帧图片，尺寸至少 320x240 且像素总量不超过 4000 万")
        }
        let allowed: [UTType] = [.png, .jpeg, .heic, .tiff, .webP]
        guard let imageType = UTType(type as String), allowed.contains(where: { imageType.conforms(to: $0) }) else {
            throw ThemeServiceError.invalidBackground("仅支持 PNG、JPEG、HEIC、TIFF 或 WebP 图片")
        }

        let normalized = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(normalized, UTType.png.identifier as CFString, 1, nil) else {
            throw ThemeServiceError.invalidBackground("无法规范化背景图片")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), normalized.length <= 16 * 1_024 * 1_024 else {
            throw ThemeServiceError.invalidBackground("规范化后的 PNG 图片超过 16 MB")
        }
        let fileName = "background-\(UUID().uuidString).png"
        try fileManager.createDirectory(at: backgroundDirectoryURL, withIntermediateDirectories: true)
        try secureWrite(normalized as Data, to: backgroundDirectoryURL.appendingPathComponent(fileName))
        return BackgroundImportResult(imageName: fileName, suggestedAccent: suggestedAccent(from: image))
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

    public func copyBackground(named name: String?) throws -> String? {
        guard let name else { return nil }
        guard let source = backgroundURL(named: name) else {
            throw ThemeServiceError.invalidBackground("已选择的图片不存在，请重新选择")
        }
        let data = try limitedData(from: source, maximumBytes: 16 * 1_024 * 1_024)
        let copyName = "background-\(UUID().uuidString).png"
        try secureWrite(data, to: backgroundDirectoryURL.appendingPathComponent(copyName))
        return copyName
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

    private func suggestedAccent(from image: CGImage) -> String? {
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var best: (red: UInt8, green: UInt8, blue: UInt8, score: Double)?
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] >= 128 {
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            guard saturation >= 0.25, luminance >= 0.16, luminance <= 0.88 else { continue }
            let score = saturation * (1 - abs(luminance - 0.55))
            if score > (best?.score ?? -1) {
                best = (pixels[offset], pixels[offset + 1], pixels[offset + 2], score)
            }
        }
        guard let best else { return nil }
        return String(format: "#%02X%02X%02X", best.red, best.green, best.blue)
    }
}
