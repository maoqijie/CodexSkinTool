import Foundation

public struct TOMLDocumentEditor: Sendable {
    static let managedKeys = [
        "appearanceTheme",
        "appearanceLightCodeThemeId",
        "appearanceDarkCodeThemeId",
        "appearanceLightChromeTheme",
        "appearanceDarkChromeTheme",
    ]
    static let chromeKeys = ["appearanceLightChromeTheme", "appearanceDarkChromeTheme"]

    public init() {}

    public func appearanceBaseline(from data: Data) throws -> AppearanceBaseline {
        guard let source = String(data: data, encoding: .utf8) else {
            throw ThemeServiceError.invalidConfiguration("配置文件不是有效的 UTF-8 文本")
        }
        var values: [String: String] = [:]
        var chromeSections: [String: String] = [:]
        for key in Self.managedKeys {
            if let range = try uniqueValue(for: key, inSection: "desktop", source: source) {
                values[key] = String(source[range])
            }
        }
        for key in Self.chromeKeys {
            if let range = try sectionGroupRange(named: "desktop.\(key)", in: source) {
                guard values[key] == nil else {
                    throw ThemeServiceError.invalidConfiguration("\(key) 同时使用内联值和子表")
                }
                chromeSections[key] = String(source[range])
            }
        }
        return AppearanceBaseline(values: values, chromeSections: chromeSections)
    }

    public func restoringAppearance(
        in currentData: Data,
        baseline: AppearanceBaseline
    ) throws -> Data {
        guard let current = String(data: currentData, encoding: .utf8) else {
            throw ThemeServiceError.invalidConfiguration("配置文件不是有效的 UTF-8 文本")
        }
        let newline = current.contains("\r\n") ? "\r\n" : "\n"
        var result = current

        for key in Self.managedKeys {
            if Self.chromeKeys.contains(key) {
                result = try removingSectionGroup(named: "desktop.\(key)", from: result)
            }
            let currentValue = try uniqueValue(for: key, inSection: "desktop", source: result)
            if let baselineValue = baseline.values[key] {
                if let currentValue {
                    result.replaceSubrange(currentValue, with: baselineValue)
                } else {
                    result = insert(
                        key: key,
                        value: baselineValue,
                        inSection: "desktop",
                        source: result,
                        newline: newline
                    )
                }
            } else if currentValue != nil,
                      let assignment = try uniqueAssignment(for: key, inSection: "desktop", source: result) {
                result.removeSubrange(assignment)
            }
        }
        for key in Self.chromeKeys {
            if let section = baseline.chromeSections[key] {
                result = appendingSectionGroup(section, to: result, newline: newline)
            }
        }

        guard let output = result.data(using: .utf8) else {
            throw ThemeServiceError.invalidConfiguration("无法编码恢复后的配置")
        }
        return output
    }

    public func applying(theme: Theme, to data: Data) throws -> Data {
        guard let source = String(data: data, encoding: .utf8) else {
            throw ThemeServiceError.invalidConfiguration("配置文件不是有效的 UTF-8 文本")
        }
        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        let values = values(for: theme)
        var result = source

        for (key, value) in values {
            if Self.chromeKeys.contains(key) {
                let sectionName = "desktop.\(key)"
                let sectionExists = try sectionGroupRange(named: sectionName, in: result) != nil
                if sectionExists,
                   try uniqueValue(for: key, inSection: "desktop", source: result) != nil {
                    throw ThemeServiceError.invalidConfiguration("\(key) 同时使用内联值和子表")
                }
                result = try removingSectionGroup(named: sectionName, from: result)
            }
            if let range = try uniqueValue(for: key, inSection: "desktop", source: result) {
                result.replaceSubrange(range, with: value)
            } else {
                result = insert(key: key, value: value, inSection: "desktop", source: result, newline: newline)
            }
        }
        guard let output = result.data(using: .utf8) else {
            throw ThemeServiceError.invalidConfiguration("无法编码更新后的配置")
        }
        return output
    }

    public func restoringAppearance(in currentData: Data, from baselineData: Data) throws -> Data {
        guard String(data: currentData, encoding: .utf8) != nil,
              String(data: baselineData, encoding: .utf8) != nil else {
            throw ThemeServiceError.invalidConfiguration("配置文件不是有效的 UTF-8 文本")
        }
        for theme in ThemeCatalog.builtIn where try applying(theme: theme, to: baselineData) == currentData {
            return baselineData
        }
        return try restoringAppearance(in: currentData, baseline: appearanceBaseline(from: baselineData))
    }

    public func isEffectivelyEmpty(_ data: Data) -> Bool {
        guard let source = String(data: data, encoding: .utf8) else { return false }
        let meaningfulLines = source.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed != "[desktop]"
        }
        return meaningfulLines.isEmpty
    }

    private func values(for theme: Theme) -> [(String, String)] {
        let prefix = theme.mode == .light ? "appearanceLight" : "appearanceDark"
        return [
            ("appearanceTheme", quoted(theme.mode.rawValue)),
            ("\(prefix)CodeThemeId", quoted(theme.codeThemeId)),
            ("\(prefix)ChromeTheme", inlineTable(theme.chromeTheme))
        ]
    }

    private func inlineTable(_ theme: ChromeTheme) -> String {
        let fonts = "{ code = \(nullable(theme.fonts.code)), ui = \(nullable(theme.fonts.ui)) }"
        let semantic = "{ diffAdded = \(quoted(theme.semanticColors.diffAdded)), "
            + "diffRemoved = \(quoted(theme.semanticColors.diffRemoved)), "
            + "skill = \(quoted(theme.semanticColors.skill)) }"
        return "{ accent = \(quoted(theme.accent)), ink = \(quoted(theme.ink)), "
            + "surface = \(quoted(theme.surface)), contrast = \(theme.contrast), "
            + "fonts = \(fonts), opaqueWindows = \(theme.opaqueWindows), "
            + "semanticColors = \(semantic) }"
    }

    private func nullable(_ value: String?) -> String {
        value.map(quoted) ?? "\"\""
    }

    private func quoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func uniqueValue(
        for key: String,
        inSection section: String,
        source: String
    ) throws -> Range<String.Index>? {
        let matches = valueRanges(for: key, inSection: section, source: source)
        guard matches.count <= 1 else {
            throw ThemeServiceError.invalidConfiguration("[\(section)] 中存在重复键 \(key)")
        }
        return matches.first
    }

    private func uniqueAssignment(
        for key: String,
        inSection section: String,
        source: String
    ) throws -> Range<String.Index>? {
        guard let sectionRange = sectionBodyRange(named: section, in: source) else { return nil }
        var matches: [Range<String.Index>] = []
        var cursor = sectionRange.lowerBound
        while cursor < sectionRange.upperBound {
            let lineEnd = source[cursor..<sectionRange.upperBound].firstIndex(where: \.isNewline)
                ?? sectionRange.upperBound
            let contentEnd = lineEnd > cursor && source[source.index(before: lineEnd)] == "\r"
                ? source.index(before: lineEnd) : lineEnd
            if let equals = assignmentEquals(key: key, in: source[cursor..<contentEnd], source: source) {
                let valueStart = skipHorizontalWhitespace(
                    from: source.index(after: equals),
                    limit: sectionRange.upperBound,
                    source: source
                )
                let value = scannedValueRange(from: valueStart, limit: sectionRange.upperBound, source: source)
                let endOfValueLine = source[value.upperBound..<sectionRange.upperBound].firstIndex(where: \.isNewline)
                    ?? sectionRange.upperBound
                let assignmentEnd = endOfValueLine < sectionRange.upperBound
                    ? source.index(after: endOfValueLine) : endOfValueLine
                matches.append(cursor..<assignmentEnd)
            }
            cursor = lineEnd < sectionRange.upperBound ? source.index(after: lineEnd) : sectionRange.upperBound
        }
        guard matches.count <= 1 else {
            throw ThemeServiceError.invalidConfiguration("[\(section)] 中存在重复键 \(key)")
        }
        return matches.first
    }

    private func valueRanges(
        for key: String,
        inSection section: String,
        source: String
    ) -> [Range<String.Index>] {
        guard let sectionRange = sectionBodyRange(named: section, in: source) else { return [] }
        var matches: [Range<String.Index>] = []
        var cursor = sectionRange.lowerBound
        while cursor < sectionRange.upperBound {
            let lineEnd = source[cursor..<sectionRange.upperBound].firstIndex(where: \.isNewline)
                ?? sectionRange.upperBound
            let contentEnd = lineEnd > cursor && source[source.index(before: lineEnd)] == "\r"
                ? source.index(before: lineEnd) : lineEnd
            if let equals = assignmentEquals(key: key, in: source[cursor..<contentEnd], source: source) {
                let valueStart = skipHorizontalWhitespace(
                    from: source.index(after: equals),
                    limit: sectionRange.upperBound,
                    source: source
                )
                matches.append(scannedValueRange(from: valueStart, limit: sectionRange.upperBound, source: source))
            }
            cursor = lineEnd < sectionRange.upperBound ? source.index(after: lineEnd) : sectionRange.upperBound
        }
        return matches
    }

    private func assignmentEquals(
        key: String,
        in line: Substring,
        source: String
    ) -> String.Index? {
        var index = line.startIndex
        while index < line.endIndex && (source[index] == " " || source[index] == "\t") {
            index = source.index(after: index)
        }
        guard source[index...].hasPrefix(key) else { return nil }
        index = source.index(index, offsetBy: key.count)
        guard index <= line.endIndex else { return nil }
        while index < line.endIndex && (source[index] == " " || source[index] == "\t") {
            index = source.index(after: index)
        }
        guard index < line.endIndex, source[index] == "=" else { return nil }
        return index
    }

    private func scannedValueRange(
        from start: String.Index,
        limit: String.Index,
        source: String
    ) -> Range<String.Index> {
        var index = start
        var depth = 0
        var quote: Character?
        var escaped = false
        var lastValueEnd = start

        while index < limit {
            let character = source[index]
            let next = source.index(after: index)
            if let activeQuote = quote {
                if activeQuote == "\"" && character == "\\" && !escaped {
                    escaped = true
                } else {
                    if character == activeQuote && !escaped { quote = nil }
                    escaped = false
                }
                lastValueEnd = next
            } else {
                if character == "\"" || character == "'" {
                    quote = character
                    lastValueEnd = next
                } else if character == "{" || character == "[" {
                    depth += 1
                    lastValueEnd = next
                } else if character == "}" || character == "]" {
                    depth = max(0, depth - 1)
                    lastValueEnd = next
                } else if character == "#" && depth == 0 {
                    break
                } else if character.isNewline && depth == 0 {
                    break
                } else if character != " " && character != "\t" && character != "\r" && character != "\n" {
                    lastValueEnd = next
                }
            }
            index = next
        }
        return start..<lastValueEnd
    }

    private func insert(key: String, value: String, inSection section: String, source: String, newline: String) -> String {
        let assignment = "\(key) = \(value)\(newline)"
        guard let location = insertionLocation(forSection: section, in: source) else {
            let separator = source.isEmpty || source.last?.isNewline == true ? "" : newline
            return source + separator + "[\(section)]\(newline)" + assignment
        }
        var result = source
        let prefix = location == source.endIndex && source.last?.isNewline != true ? newline : ""
        result.insert(contentsOf: prefix + assignment, at: location)
        return result
    }

    private func insertionLocation(forSection name: String, in source: String) -> String.Index? {
        var cursor = source.startIndex
        var firstChildSection: String.Index?
        var inTargetSection = false
        while cursor < source.endIndex {
            let lineEnd = source[cursor...].firstIndex(where: \.isNewline) ?? source.endIndex
            var contentEnd = lineEnd
            if contentEnd > cursor && source[source.index(before: contentEnd)] == "\r" {
                contentEnd = source.index(before: contentEnd)
            }
            let trimmed = source[cursor..<contentEnd].trimmingCharacters(in: .whitespaces)
            if let header = tableHeader(in: trimmed) {
                if header == name {
                    inTargetSection = true
                } else if inTargetSection {
                    if header.hasPrefix("\(name).") {
                        firstChildSection = firstChildSection ?? cursor
                    } else {
                        return firstChildSection ?? cursor
                    }
                }
            }
            cursor = lineEnd < source.endIndex ? source.index(after: lineEnd) : source.endIndex
        }
        return inTargetSection ? (firstChildSection ?? source.endIndex) : nil
    }

    private func sectionBodyRange(named name: String, in source: String) -> Range<String.Index>? {
        var cursor = source.startIndex
        var bodyStart: String.Index?
        while cursor < source.endIndex {
            let lineEnd = source[cursor...].firstIndex(where: \.isNewline) ?? source.endIndex
            var contentEnd = lineEnd
            if contentEnd > cursor && source[source.index(before: contentEnd)] == "\r" {
                contentEnd = source.index(before: contentEnd)
            }
            let trimmed = source[cursor..<contentEnd].trimmingCharacters(in: .whitespaces)
            if let header = tableHeader(in: trimmed) {
                if let start = bodyStart { return start..<cursor }
                if header == name {
                    bodyStart = lineEnd < source.endIndex ? source.index(after: lineEnd) : source.endIndex
                }
            }
            cursor = lineEnd < source.endIndex ? source.index(after: lineEnd) : source.endIndex
        }
        return bodyStart.map { $0..<source.endIndex }
    }

    func tableHeader(in line: String) -> String? {
        guard line.hasPrefix("["), !line.hasPrefix("[["), let close = line.firstIndex(of: "]") else {
            return nil
        }
        let remainder = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard remainder.isEmpty || remainder.hasPrefix("#") else { return nil }
        return String(line[line.index(after: line.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
    }

    private func skipHorizontalWhitespace(
        from start: String.Index,
        limit: String.Index,
        source: String
    ) -> String.Index {
        var index = start
        while index < limit && (source[index] == " " || source[index] == "\t") {
            index = source.index(after: index)
        }
        return index
    }
}
