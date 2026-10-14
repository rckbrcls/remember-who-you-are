import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy = "Easy", medium = "Medium", hard = "Hard"
}

public struct Problem: Codable, Identifiable, Equatable, Sendable {
    public let title: String
    public let slug: String
    public let difficulty: Difficulty
    public let tags: [String]
    public let minutes: Int

    public var id: String { slug }
    public var url: URL { URL(string: "https://leetcode.com/problems/\(slug)/")! }

    public init(_ title: String, _ slug: String, _ difficulty: Difficulty, _ tags: [String], _ minutes: Int) {
        self.title = title; self.slug = slug; self.difficulty = difficulty; self.tags = tags; self.minutes = minutes
    }
}

public enum ProblemCatalog {
    public static let all: [Problem] = {
        guard let data = CatalogData.json.data(using: .utf8),
              let problems = try? JSONDecoder().decode([Problem].self, from: data)
        else { return [] }
        return problems
    }()
}
