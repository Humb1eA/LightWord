import Foundation

/// Today's counters plus the long-running streak. Everything resets per day,
/// which keeps the "did I finish today" question a single integer comparison.
public struct StudyLog: Codable, Equatable, Sendable {
    public var day: DayKey?
    public var newCount: Int
    public var reviewCount: Int
    public var answered: Int
    public var correct: Int
    public var streak: Int
    public var bestStreak: Int
    public var lastStudyDay: DayKey?

    public init(
        day: DayKey? = nil,
        newCount: Int = 0,
        reviewCount: Int = 0,
        answered: Int = 0,
        correct: Int = 0,
        streak: Int = 0,
        bestStreak: Int = 0,
        lastStudyDay: DayKey? = nil
    ) {
        self.day = day
        self.newCount = newCount
        self.reviewCount = reviewCount
        self.answered = answered
        self.correct = correct
        self.streak = streak
        self.bestStreak = bestStreak
        self.lastStudyDay = lastStudyDay
    }

    /// Moves the counters to `today`, zeroing today's numbers when the calendar
    /// day changed. The streak is only *broken* here; it grows in `touch`.
    public mutating func rollover(to today: DayKey) {
        guard day != today else { return }
        day = today
        newCount = 0
        reviewCount = 0
        answered = 0
        correct = 0
        if let last = lastStudyDay, today.raw - last.raw > 1 {
            streak = 0
        }
    }

    /// Records that the user studied today and advances the streak at most once
    /// per calendar day.
    public mutating func touch(today: DayKey) {
        if lastStudyDay == today { return }
        if let last = lastStudyDay, today.raw - last.raw == 1 {
            streak += 1
        } else {
            streak = 1
        }
        lastStudyDay = today
        bestStreak = max(bestStreak, streak)
    }

    /// Streak as it should be *displayed*: a streak survives until the day after
    /// tomorrow, so yesterday's study still shows today.
    public func displayStreak(today: DayKey) -> Int {
        guard let last = lastStudyDay else { return 0 }
        let gap = today.raw - last.raw
        return gap <= 1 ? streak : 0
    }

    public var accuracy: Double {
        answered > 0 ? Double(correct) / Double(answered) : 0
    }
}

public struct LearningState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var bookID: String
    public var cards: [String: CardState]
    public var settings: Settings
    public var log: StudyLog

    public init(
        schemaVersion: Int = 1,
        bookID: String = "",
        cards: [String: CardState] = [:],
        settings: Settings = Settings(),
        log: StudyLog = StudyLog()
    ) {
        self.schemaVersion = schemaVersion
        self.bookID = bookID
        self.cards = cards
        self.settings = settings
        self.log = log
    }

    public var learnedCount: Int {
        cards.values.filter { !$0.isNew }.count
    }

    public var starredCount: Int {
        cards.values.filter { $0.starred }.count
    }

    public func dueCount(today: DayKey) -> Int {
        cards.values.filter { !$0.isNew && $0.due <= today }.count
    }
}
