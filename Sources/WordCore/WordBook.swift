import Foundation

public struct WordBook: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let words: [Word]

    public init(id: String, name: String, detail: String, words: [Word]) {
        self.id = id
        self.name = name
        self.detail = detail
        self.words = words
    }

    public func word(id: String) -> Word? {
        words.first { $0.id == id }
    }

    public var index: [String: Word] {
        Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case detail = "description"
        case words
    }
}

public enum WordBookLoader {
    public static func decode(_ data: Data) throws -> WordBook {
        try JSONDecoder().decode(WordBook.self, from: data)
    }
}
