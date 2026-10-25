import Foundation

extension WordBookLoader {
    /// Reads the word book that `tools/build-ipa.sh` copies into `Wordbooks/`.
    static func loadBundled(name: String = "gaokao") -> WordBook? {
        let bundle = Bundle.main
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Wordbooks")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}
