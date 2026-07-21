import Foundation

public struct AppearanceBaseline: Codable, Equatable, Sendable {
    public let values: [String: String]
    public let chromeSections: [String: String]

    public init(
        values: [String: String] = [:],
        chromeSections: [String: String] = [:]
    ) {
        self.values = values
        self.chromeSections = chromeSections
    }
}
