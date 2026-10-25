import Foundation

/// Per-word learning progress. `box` is the index into `Scheduler.intervals`:
/// 0 means "never graded", 1 is the first learning step, 8 is the last.
public struct CardState: Codable, Hashable, Sendable {
    public var box: Int
    public var due: DayKey
    public var reps: Int
    public var lapses: Int
    public var lastReviewed: DayKey?
    public var starred: Bool

    public init(
        box: Int = 0,
        due: DayKey,
        reps: Int = 0,
        lapses: Int = 0,
        lastReviewed: DayKey? = nil,
        starred: Bool = false
    ) {
        self.box = box
        self.due = due
        self.reps = reps
        self.lapses = lapses
        self.lastReviewed = lastReviewed
        self.starred = starred
    }

    public var isNew: Bool { box == 0 }
}

public enum Scheduler {
    /// Days until a card in `box` comes around again. Index 0 is box 1.
    public static let intervals: [Int] = [1, 1, 2, 4, 7, 15, 30, 60, 120]

    public static let maxBox: Int = intervals.count

    public static func newCard(today: DayKey) -> CardState {
        CardState(box: 0, due: today)
    }

    /// Leitner-style grading: a hit moves the card one box down the ladder, a
    /// miss drops it back to the first box and counts a lapse.
    public static func grade(
        state: CardState,
        correct: Bool,
        today: DayKey,
        calendar: Calendar = .current
    ) -> CardState {
        var next = state
        next.reps += 1
        next.lastReviewed = today

        if correct {
            next.box = min(state.box + 1, Scheduler.maxBox)
        } else {
            next.box = 1
            next.lapses += 1
        }

        let intervalIndex = min(max(next.box - 1, 0), Scheduler.intervals.count - 1)
        next.due = today.adding(Scheduler.intervals[intervalIndex], calendar: calendar)
        return next
    }

    public static func isDue(_ state: CardState?, today: DayKey) -> Bool {
        guard let state else { return true }
        return state.due <= today
    }
}
