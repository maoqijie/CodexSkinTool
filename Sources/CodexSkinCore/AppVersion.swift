import Foundation

public struct AppVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    public init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.first.map { $0 == "v" || $0 == "V" } == true
            ? String(trimmed.dropFirst())
            : trimmed
        guard !normalized.isEmpty else { return nil }

        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return nil }
            return Int(part)
        }
        guard numbers.count == parts.count else { return nil }
        components = numbers
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
