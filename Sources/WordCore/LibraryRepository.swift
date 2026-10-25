import Foundation

/// File I/O for the whole learning state — one small JSON document in
/// Application Support. No Core Data, no database, nothing to migrate at launch.
public struct LibraryRepository: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("LightWord", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// `nil` on missing/corrupt file; callers start from a fresh state instead of
    /// crashing on launch.
    public func load(fileManager: FileManager = .default) -> LearningState? {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        return try? LibraryRepository.makeDecoder().decode(LearningState.self, from: data)
    }

    public func save(_ state: LearningState, fileManager: FileManager = .default) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try LibraryRepository.makeEncoder().encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}
