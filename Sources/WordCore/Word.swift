import Foundation

public struct Example: Hashable, Codable, Sendable {
    public let en: String
    public let zh: String

    public init(en: String, zh: String) {
        self.en = en
        self.zh = zh
    }
}

/// One dictionary entry. Field names are short (`i`, `w`, `p`, `m`, `e`) because
/// the word book ships inside the app bundle and is decoded on launch.
public struct Word: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let text: String
    public let phonetic: String
    public let meanings: [String]
    public let examples: [Example]

    public init(id: String, text: String, phonetic: String, meanings: [String], examples: [Example] = []) {
        self.id = id
        self.text = text
        self.phonetic = phonetic
        self.meanings = meanings
        self.examples = examples
    }

    public var primaryMeaning: String {
        meanings.first ?? ""
    }

    /// "n. 计划" -> "n." / "计划"
    public var partOfSpeech: String {
        let head = primaryMeaning.prefix(while: { $0 != " " })
        return head.hasSuffix(".") ? String(head) : ""
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i"
        case text = "w"
        case phonetic = "p"
        case meanings = "m"
        case examples = "e"
    }

    /// Tolerant decoding: the bundled 3500-word book ships no examples and a few
    /// entries have no phonetic; one missing key must not fail the whole book.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.text = try container.decode(String.self, forKey: .text)
        self.phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        self.meanings = try container.decodeIfPresent([String].self, forKey: .meanings) ?? []
        self.examples = try container.decodeIfPresent([Example].self, forKey: .examples) ?? []
    }
}
