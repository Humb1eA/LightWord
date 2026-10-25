import Foundation

public struct SessionItem: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case fresh
        case review
    }

    public let id: String
    public let word: Word
    public let kind: Kind
    public let state: CardState

    public init(id: String, word: Word, kind: Kind, state: CardState) {
        self.id = id
        self.word = word
        self.kind = kind
        self.state = state
    }
}

public struct StudySession: Sendable {
    public let items: [SessionItem]

    public init(items: [SessionItem]) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }
    public var newCount: Int { items.filter { $0.kind == .fresh }.count }
    public var reviewCount: Int { items.filter { $0.kind == .review }.count }
}

public enum SessionBuilder {

    /// Builds one study session: the remaining new-word allowance first (in word
    /// book order, so progress is predictable), then everything that came due.
    ///
    /// - Parameters:
    ///   - newDoneToday: new words already studied today, subtracted from the goal.
    ///   - reviewDoneToday: reviews already studied today, subtracted from the cap.
    public static func build(
        words: [Word],
        cards: [String: CardState],
        today: DayKey,
        settings: Settings,
        newDoneToday: Int = 0,
        reviewDoneToday: Int = 0
    ) -> StudySession {
        let freshBudget = max(settings.dailyNewWords - newDoneToday, 0)
        let reviewBudget = max(settings.dailyReviewCap - reviewDoneToday, 0)

        var fresh: [SessionItem] = []
        if freshBudget > 0 {
            for word in words {
                if fresh.count >= freshBudget { break }
                if let existing = cards[word.id], !existing.isNew { continue }
                let state = cards[word.id] ?? Scheduler.newCard(today: today)
                fresh.append(SessionItem(id: word.id, word: word, kind: .fresh, state: state))
            }
        }

        var reviews: [SessionItem] = []
        if reviewBudget > 0 {
            let byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, state) in cards where !state.isNew && state.due <= today {
                guard let word = byID[id] else { continue }
                reviews.append(SessionItem(id: id, word: word, kind: .review, state: state))
            }
            // Most overdue first, then the lowest box (weakest cards) first.
            reviews.sort { lhs, rhs in
                if lhs.state.due != rhs.state.due { return lhs.state.due < rhs.state.due }
                if lhs.state.box != rhs.state.box { return lhs.state.box < rhs.state.box }
                return lhs.id < rhs.id
            }
            if reviews.count > reviewBudget {
                reviews = Array(reviews.prefix(reviewBudget))
            }
        }

        return StudySession(items: fresh + reviews)
    }

    /// True when today's plan still has something in it.
    public static func hasWork(
        words: [Word],
        cards: [String: CardState],
        today: DayKey,
        settings: Settings,
        newDoneToday: Int = 0,
        reviewDoneToday: Int = 0
    ) -> Bool {
        !build(
            words: words,
            cards: cards,
            today: today,
            settings: settings,
            newDoneToday: newDoneToday,
            reviewDoneToday: reviewDoneToday
        ).isEmpty
    }
}
