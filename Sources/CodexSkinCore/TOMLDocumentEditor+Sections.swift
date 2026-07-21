import Foundation

extension TOMLDocumentEditor {
    func sectionGroupRange(named name: String, in source: String) throws -> Range<String.Index>? {
        var cursor = source.startIndex
        var groupStart: String.Index?
        var matches = 0

        while cursor < source.endIndex {
            let lineEnd = source[cursor...].firstIndex(where: \.isNewline) ?? source.endIndex
            let line = String(source[cursor..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let header = tableHeader(in: line) {
                if header == name {
                    matches += 1
                    guard matches == 1 else {
                        throw ThemeServiceError.invalidConfiguration("存在重复表 [\(name)]")
                    }
                    groupStart = cursor
                } else if let start = groupStart, !header.hasPrefix("\(name).") {
                    return start..<cursor
                }
            }
            cursor = lineEnd < source.endIndex ? source.index(after: lineEnd) : source.endIndex
        }
        return groupStart.map { $0..<source.endIndex }
    }

    func removingSectionGroup(named name: String, from source: String) throws -> String {
        guard let range = try sectionGroupRange(named: name, in: source) else { return source }
        var result = source
        result.removeSubrange(range)
        return result
    }

    func appendingSectionGroup(_ block: String, to source: String, newline: String) -> String {
        guard !block.isEmpty else { return source }
        let separator = source.isEmpty || source.last?.isNewline == true ? "" : newline
        return source + separator + block
    }
}
