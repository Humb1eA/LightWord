import Foundation
import XCTest
@testable import WordCore

enum TestSupport {
    static func calendar(timeZone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    static func day(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> DayKey {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        let date = calendar.date(from: parts)!
        return DayKey(containing: date, calendar: calendar)
    }

    static func word(_ id: String, meaning: String? = nil) -> Word {
        Word(id: id, text: id.uppercased(), phonetic: "x", meanings: [meaning ?? "释义-\(id)"])
    }

    /// Path to the repository root, derived from this file's location:
    /// <root>/Tests/CoreTests/WordCoreTests.swift -> <root>.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <root>
    }

    /// Guards against the word-book test silently skipping because of a wrong path.
    static var wordBookURL: URL {
        repoRoot.appendingPathComponent("Resources/Wordbooks/gaokao.json")
    }
}

/// Deterministic generator so quiz shuffles can be asserted exactly.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class DayKeyTests: XCTestCase {
    private let calendar = TestSupport.calendar()

    func testEpochIsZero() {
        XCTAssertEqual(TestSupport.day(1970, 1, 1, calendar: calendar).raw, 0)
    }

    /// 20103 is verified independently by tools/reference_scheduler.py.
    func testKnownOffset() {
        XCTAssertEqual(TestSupport.day(2025, 1, 15, calendar: calendar).raw, 20103)
    }

    func testAddingDays() {
        let today = TestSupport.day(2025, 1, 15, calendar: calendar)
        XCTAssertEqual(today.adding(1, calendar: calendar).isoString(calendar: calendar), "2025-01-16")
        XCTAssertEqual(today.adding(-1, calendar: calendar).isoString(calendar: calendar), "2025-01-14")
        XCTAssertEqual(today.adding(0, calendar: calendar), today)
    }

    func testAddingDaysAcrossDaylightSavingTransitions() {
        let eastern = TestSupport.calendar(timeZone: "America/New_York")

        let springForward = TestSupport.day(2024, 3, 10, calendar: eastern)
        XCTAssertEqual(springForward.adding(1, calendar: eastern).isoString(calendar: eastern), "2024-03-11")
        XCTAssertEqual(springForward.adding(1, calendar: eastern).raw, springForward.raw + 1)

        let fallBack = TestSupport.day(2024, 11, 3, calendar: eastern)
        XCTAssertEqual(fallBack.adding(1, calendar: eastern).isoString(calendar: eastern), "2024-11-04")
        XCTAssertEqual(fallBack.adding(1, calendar: eastern).raw, fallBack.raw + 1)
    }

    func testIsoStringPadsMonthAndDay() {
        XCTAssertEqual(
            TestSupport.day(2025, 3, 7, calendar: calendar).isoString(calendar: calendar),
            "2025-03-07"
        )
    }

    func testEncodesAsBareInteger() throws {
        let key = TestSupport.day(2025, 1, 15, calendar: calendar)
        let data = try JSONEncoder().encode(key)
        XCTAssertEqual(String(data: data, encoding: .utf8), "20103")
        XCTAssertEqual(try JSONDecoder().decode(DayKey.self, from: data), key)
    }
}

final class SchedulerTests: XCTestCase {
    private let calendar = TestSupport.calendar()
    private var today: DayKey { TestSupport.day(2025, 1, 15, calendar: calendar) }

    /// Values match tools/reference_scheduler.py ("correct ladder").
    func testCorrectLadder() {
        var state = Scheduler.newCard(today: today)
        let expected: [(box: Int, due: String)] = [
            (1, "2025-01-16"),
            (2, "2025-01-16"),
            (3, "2025-01-17"),
            (4, "2025-01-19"),
            (5, "2025-01-22"),
            (6, "2025-01-30"),
            (7, "2025-02-14"),
            (8, "2025-03-16"),
            (9, "2025-05-15")
        ]

        for (index, want) in expected.enumerated() {
            state = Scheduler.grade(state: state, correct: true, today: today, calendar: calendar)
            XCTAssertEqual(state.box, want.box, "box after \(index + 1) hits")
            XCTAssertEqual(state.due.isoString(calendar: calendar), want.due, "due after \(index + 1) hits")
        }
        XCTAssertEqual(state.reps, 9)
    }

    func testBoxNeverExceedsTheLadder() {
        var state = CardState(box: Scheduler.maxBox, due: today, reps: 20)
        state = Scheduler.grade(state: state, correct: true, today: today, calendar: calendar)
        XCTAssertEqual(state.box, Scheduler.maxBox)
        XCTAssertEqual(state.due, today.adding(Scheduler.intervals[Scheduler.maxBox - 1], calendar: calendar))
    }

    func testMissResetsToFirstBoxAndCountsLapse() {
        let state = CardState(box: 6, due: today, reps: 6, lapses: 2, starred: true)
        let next = Scheduler.grade(state: state, correct: false, today: today, calendar: calendar)

        XCTAssertEqual(next.box, 1)
        XCTAssertEqual(next.lapses, 3)
        XCTAssertEqual(next.reps, 7)
        XCTAssertEqual(next.due, today.adding(1, calendar: calendar))
        XCTAssertTrue(next.starred, "star must survive grading")
    }

    func testIsDue() {
        let overdue = CardState(box: 2, due: today.adding(-1, calendar: calendar))
        let dueToday = CardState(box: 2, due: today)
        let tomorrow = CardState(box: 2, due: today.adding(1, calendar: calendar))

        XCTAssertTrue(Scheduler.isDue(overdue, today: today))
        XCTAssertTrue(Scheduler.isDue(dueToday, today: today))
        XCTAssertFalse(Scheduler.isDue(tomorrow, today: today))
        XCTAssertTrue(Scheduler.isDue(nil, today: today), "unseen cards are always available")
    }
}

final class SessionBuilderTests: XCTestCase {
    private let calendar = TestSupport.calendar()
    private var today: DayKey { TestSupport.day(2025, 1, 15, calendar: calendar) }

    private var words: [Word] {
        ["w1", "w2", "w3", "w4", "w5", "w6"].map { TestSupport.word($0) }
    }

    /// w1 overdue, w2 more overdue, w3 due today, w4 due tomorrow, w5 unseen
    /// with a box-0 card, w6 completely unseen.
    private func cards() -> [String: CardState] {
        [
            "w1": CardState(box: 2, due: today.adding(-1, calendar: calendar)),
            "w2": CardState(box: 1, due: today.adding(-3, calendar: calendar)),
            "w3": CardState(box: 1, due: today),
            "w4": CardState(box: 1, due: today.adding(1, calendar: calendar)),
            "w5": CardState(box: 0, due: today)
        ]
    }

    private func ids(_ session: StudySession) -> [String] {
        session.items.map(\.id)
    }

    func testNewWordsComeFirstThenMostOverdueReviews() {
        let session = SessionBuilder.build(
            words: words,
            cards: cards(),
            today: today,
            settings: Settings(dailyNewWords: 3, dailyReviewCap: 60)
        )

        XCTAssertEqual(ids(session), ["w5", "w6", "w2", "w1", "w3"])
        XCTAssertEqual(session.newCount, 2)
        XCTAssertEqual(session.reviewCount, 3)
        XCTAssertEqual(session.items[0].kind, .fresh)
        XCTAssertEqual(session.items[2].kind, .review)
    }

    func testAlreadyStudiedNewWordsReduceTheBudget() {
        let session = SessionBuilder.build(
            words: words,
            cards: cards(),
            today: today,
            settings: Settings(dailyNewWords: 3, dailyReviewCap: 60),
            newDoneToday: 2
        )
        XCTAssertEqual(ids(session), ["w5", "w2", "w1", "w3"])
    }

    func testReviewCapIsHonoured() {
        let session = SessionBuilder.build(
            words: words,
            cards: cards(),
            today: today,
            settings: Settings(dailyNewWords: 3, dailyReviewCap: 60),
            reviewDoneToday: 60
        )
        XCTAssertEqual(ids(session), ["w5", "w6"])
    }

    func testNothingToDoWhenQuotasAreMet() {
        let session = SessionBuilder.build(
            words: words,
            cards: cards(),
            today: today,
            settings: Settings(dailyNewWords: 3, dailyReviewCap: 60),
            newDoneToday: 3,
            reviewDoneToday: 60
        )
        XCTAssertTrue(session.isEmpty)
    }

    func testCardsDueLaterStayOut() {
        let session = SessionBuilder.build(
            words: words,
            cards: cards(),
            today: today,
            settings: Settings(dailyNewWords: 5, dailyReviewCap: 60)
        )
        XCTAssertFalse(ids(session).contains("w4"))
    }

    func testHasWorkMatchesBuild() {
        let settings = Settings(dailyNewWords: 3, dailyReviewCap: 60)
        XCTAssertTrue(
            SessionBuilder.hasWork(words: words, cards: cards(), today: today, settings: settings)
        )
        XCTAssertFalse(
            SessionBuilder.hasWork(
                words: words,
                cards: cards(),
                today: today,
                settings: settings,
                newDoneToday: 3,
                reviewDoneToday: 60
            )
        )
    }
}

final class QuizTests: XCTestCase {
    private var pool: [Word] {
        (0..<8).map { TestSupport.word("q\($0)", meaning: "释义\($0)") }
    }

    func testOptionsContainTheAnswerAndAreDistinct() {
        let answer = pool[3]
        var rng = SeededRNG(seed: 42)
        let options = Quiz.options(for: answer, pool: pool, rng: &rng)

        XCTAssertEqual(options.count, 4)
        XCTAssertTrue(options.contains { $0.id == answer.id })

        let meanings = options.map(\.primaryMeaning)
        XCTAssertEqual(Set(meanings).count, meanings.count, "distractors must not repeat a meaning")
    }

    func testOptionsAreStableForTheSameSeed() {
        let answer = pool[0]
        var first = SeededRNG(seed: 7)
        var second = SeededRNG(seed: 7)
        let a = Quiz.options(for: answer, pool: pool, rng: &first).map(\.id)
        let b = Quiz.options(for: answer, pool: pool, rng: &second).map(\.id)
        XCTAssertEqual(a, b)
    }

    func testFallsBackWhenThePoolIsTiny() {
        let answer = TestSupport.word("solo")
        var rng = SeededRNG(seed: 1)
        let options = Quiz.options(for: answer, pool: [answer], rng: &rng)
        XCTAssertEqual(options.map(\.id), ["solo"])
    }
}

final class StudyLogTests: XCTestCase {
    private let calendar = TestSupport.calendar()
    private var day0: DayKey { TestSupport.day(2025, 1, 15, calendar: calendar) }

    func testRolloverClearsCountersAndBreaksStreak() {
        var log = StudyLog()
        log.rollover(to: day0)
        log.touch(today: day0)
        log.newCount = 5
        log.reviewCount = 7
        log.answered = 12
        log.correct = 9
        XCTAssertEqual(log.streak, 1)

        log.rollover(to: day0.adding(1, calendar: calendar))
        XCTAssertEqual(log.newCount, 0)
        XCTAssertEqual(log.reviewCount, 0)
        XCTAssertEqual(log.correct, 0)
        XCTAssertEqual(log.streak, 1, "the next day keeps the streak alive")

        log.rollover(to: day0.adding(3, calendar: calendar))
        XCTAssertEqual(log.streak, 0, "skipping a day breaks the streak")
    }

    func testTouchIsIdempotentPerDay() {
        var log = StudyLog()
        log.rollover(to: day0)
        log.touch(today: day0)
        log.touch(today: day0)
        log.touch(today: day0)
        XCTAssertEqual(log.streak, 1)
        XCTAssertEqual(log.bestStreak, 1)
    }

    func testConsecutiveDaysIncreaseStreakOnce() {
        var log = StudyLog()
        log.rollover(to: day0)
        for offset in 0..<4 {
            let day = day0.adding(offset, calendar: calendar)
            log.rollover(to: day)
            log.touch(today: day)
        }
        XCTAssertEqual(log.streak, 4)
        XCTAssertEqual(log.bestStreak, 4)
    }

    func testDisplayStreakSurvivesYesterday() {
        var log = StudyLog()
        log.rollover(to: day0)
        log.touch(today: day0)

        XCTAssertEqual(log.displayStreak(today: day0), 1)
        XCTAssertEqual(log.displayStreak(today: day0.adding(1, calendar: calendar)), 1)
        XCTAssertEqual(log.displayStreak(today: day0.adding(2, calendar: calendar)), 0)
    }

    func testAccuracy() {
        var log = StudyLog()
        log.answered = 4
        log.correct = 3
        XCTAssertEqual(log.accuracy, 0.75, accuracy: 0.0001)
        XCTAssertEqual(StudyLog().accuracy, 0)
    }
}

final class WordBookTests: XCTestCase {
    func testDecodesEntryWithoutExamplesOrPhonetic() throws {
        let json = """
        {"i":"capable","w":"capable","m":["a. 有能力的"]}
        """.data(using: .utf8)!

        let word = try JSONDecoder().decode(Word.self, from: json)
        XCTAssertEqual(word.id, "capable")
        XCTAssertEqual(word.phonetic, "")
        XCTAssertTrue(word.examples.isEmpty)
        XCTAssertEqual(word.primaryMeaning, "a. 有能力的")
    }

    func testDecodesEntryWithExamples() throws {
        let json = """
        {"i":"abandon","w":"abandon","p":"əˈbændən","m":["v. 放弃","v. 抛弃"],
         "e":[{"en":"They abandoned the plan.","zh":"他们放弃了计划。"}]}
        """.data(using: .utf8)!

        let word = try JSONDecoder().decode(Word.self, from: json)
        XCTAssertEqual(word.phonetic, "əˈbændən")
        XCTAssertEqual(word.meanings.count, 2)
        XCTAssertEqual(word.examples.first?.zh, "他们放弃了计划。")
    }

    /// Guards the file that actually ships inside the app.
    func testBundledGaokaoBookDecodes() throws {
        let url = TestSupport.wordBookURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Never let a wrong path pass silently on CI.
            if ProcessInfo.processInfo.environment["CI"] != nil {
                XCTFail("word book missing at \(url.path)")
                return
            }
            throw XCTSkip("word book not generated yet: \(url.path)")
        }

        let book = try WordBookLoader.decode(Data(contentsOf: url))
        XCTAssertEqual(book.id, "gaokao")
        XCTAssertGreaterThan(book.words.count, 3000)
        XCTAssertEqual(Set(book.words.map(\.id)).count, book.words.count, "ids must be unique")

        let blank = book.words.filter { $0.meanings.isEmpty }
        XCTAssertTrue(blank.isEmpty, "every entry needs a meaning: \(blank.map(\.id).prefix(5))")

        let withoutPhonetic = book.words.filter { $0.phonetic.isEmpty }
        XCTAssertLessThan(Double(withoutPhonetic.count), Double(book.words.count) * 0.03)
    }

    func testRepositoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightWordTests-\(UUID().uuidString)", isDirectory: true)
        let repository = LibraryRepository(fileURL: directory.appendingPathComponent("state.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        var state = LearningState(bookID: "gaokao")
        state.cards["abandon"] = CardState(box: 2, due: DayKey(raw: 20_100), reps: 2, starred: true)
        state.settings.dailyNewWords = 15
        state.log.streak = 5

        try repository.save(state)
        let loaded = repository.load()

        XCTAssertEqual(loaded, state)
        XCTAssertEqual(repository.load()?.cards["abandon"]?.starred, true)
    }

    func testMissingFileLoadsAsNil() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely-missing-\(UUID().uuidString).json")
        XCTAssertNil(LibraryRepository(fileURL: url).load())
    }
}
