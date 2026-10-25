import Foundation

public enum Quiz {
    /// Builds the multiple-choice options for a review card: the answer plus
    /// distractors taken from the same word book, de-duplicated by meaning.
    ///
    /// The result is shuffled, so callers should compute it once per card and
    /// keep it (a SwiftUI view body recomputes constantly).
    public static func options<R: RandomNumberGenerator>(
        for word: Word,
        pool: [Word],
        count: Int = 4,
        rng: inout R
    ) -> [Word] {
        let wanted = max(count, 2)
        var seenMeanings: Set<String> = [word.primaryMeaning]
        var distractors: [Word] = []

        for candidate in pool.shuffled(using: &rng) {
            if distractors.count >= wanted - 1 { break }
            guard candidate.id != word.id else { continue }
            let meaning = candidate.primaryMeaning
            guard !seenMeanings.contains(meaning) else { continue }
            seenMeanings.insert(meaning)
            distractors.append(candidate)
        }

        var result = distractors + [word]
        result.shuffle(using: &rng)
        return result
    }
}
