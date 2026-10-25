import Combine
import Foundation

/// Owns all mutable app state: the word book, the persisted learning state and
/// the in-flight study session. Views stay dumb; every rule lives here or in
/// `WordCore`, which is what makes the logic testable off-device.
@MainActor
final class AppStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case studying
        case summary
    }

    struct VocabEntry: Identifiable {
        let word: Word
        let state: CardState

        var id: String { word.id }
    }

    @Published private(set) var book: WordBook
    @Published private(set) var state: LearningState
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var session: StudySession?
    @Published private(set) var cursor = 0
    @Published private(set) var options: [Word] = []
    @Published private(set) var sessionAnswered = 0
    @Published private(set) var sessionCorrect = 0
    @Published private(set) var loadWarning: String?

    private let repository: LibraryRepository
    private let wordIndex: [String: Word]
    private var rng = SystemRandomNumberGenerator()

    init(repository: LibraryRepository = LibraryRepository(fileURL: LibraryRepository.defaultFileURL())) {
        self.repository = repository

        let loadedBook = WordBookLoader.loadBundled(name: "gaokao")
            ?? WordBook(id: "missing", name: "词库未找到", detail: "", words: [])
        self.book = loadedBook
        self.wordIndex = loadedBook.index

        var initial = repository.load() ?? LearningState(bookID: loadedBook.id)
        if initial.bookID != loadedBook.id {
            initial.bookID = loadedBook.id
        }
        initial.log.rollover(to: DayKey.today())
        self.state = initial

        if loadedBook.words.isEmpty {
            self.loadWarning = "词库文件缺失，请重新安装 App。"
        }
    }

    // MARK: - Derived values

    var today: DayKey { DayKey.today() }

    var dueCount: Int { state.dueCount(today: today) }

    var freshRemaining: Int { max(state.settings.dailyNewWords - state.log.newCount, 0) }

    var hasWork: Bool {
        SessionBuilder.hasWork(
            words: book.words,
            cards: state.cards,
            today: today,
            settings: state.settings,
            newDoneToday: state.log.newCount,
            reviewDoneToday: state.log.reviewCount
        )
    }

    var streak: Int { state.log.displayStreak(today: today) }

    var currentItem: SessionItem? {
        guard let session, cursor >= 0, cursor < session.items.count else { return nil }
        return session.items[cursor]
    }

    var sessionTotal: Int { session?.items.count ?? 0 }

    var sessionRemaining: Int { max(sessionTotal - cursor, 0) }

    func isQuizMode(_ item: SessionItem) -> Bool {
        state.settings.quizInReview && item.kind == .review && options.count >= 2
    }

    var sessionAccuracy: Int {
        sessionAnswered > 0 ? Int((Double(sessionCorrect) / Double(sessionAnswered) * 100).rounded()) : 0
    }

    // MARK: - Session lifecycle

    func startSession() {
        var next = state
        next.log.rollover(to: today)
        state = next

        let built = SessionBuilder.build(
            words: book.words,
            cards: state.cards,
            today: today,
            settings: state.settings,
            newDoneToday: state.log.newCount,
            reviewDoneToday: state.log.reviewCount
        )
        guard !built.isEmpty else {
            session = nil
            cursor = 0
            options = []
            phase = .idle
            persist()
            return
        }

        session = built
        cursor = 0
        sessionAnswered = 0
        sessionCorrect = 0
        phase = .studying
        prepareOptions()
        persist()
    }

    /// Grades the card on screen and advances. Called once per card.
    func submit(correct: Bool) {
        guard let item = currentItem else { return }

        var next = state
        next.log.rollover(to: today)
        next.log.touch(today: today)
        if item.kind == .fresh {
            next.log.newCount += 1
        } else {
            next.log.reviewCount += 1
        }
        next.log.answered += 1
        if correct { next.log.correct += 1 }

        let previous = next.cards[item.id] ?? Scheduler.newCard(today: today)
        next.cards[item.id] = Scheduler.grade(state: previous, correct: correct, today: today)
        state = next

        sessionAnswered += 1
        if correct { sessionCorrect += 1 }
        cursor += 1

        if cursor >= (session?.items.count ?? 0) {
            phase = .summary
            options = []
        } else {
            prepareOptions()
        }
        persist()
    }

    func finishSummary() {
        phase = .idle
        session = nil
        cursor = 0
        options = []
        sessionAnswered = 0
        sessionCorrect = 0
    }

    private func prepareOptions() {
        guard let item = currentItem, state.settings.quizInReview, item.kind == .review else {
            options = []
            return
        }
        options = Quiz.options(for: item.word, pool: book.words, rng: &rng)
    }

    // MARK: - Vocabulary

    func vocabulary(query: String, starredOnly: Bool) -> [VocabEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var entries: [VocabEntry] = []

        for (id, card) in state.cards where !card.isNew {
            guard let word = wordIndex[id] else { continue }
            if starredOnly && !card.starred { continue }
            if !needle.isEmpty {
                let haystack = (word.text + " " + word.meanings.joined(separator: " ")).lowercased()
                if !haystack.contains(needle) { continue }
            }
            entries.append(VocabEntry(word: word, state: card))
        }

        return entries.sorted { $0.word.text.localizedLowercase < $1.word.text.localizedLowercase }
    }

    func word(id: String) -> Word? { wordIndex[id] }

    func cardState(for id: String) -> CardState? { state.cards[id] }

    func toggleStar(wordID: String) {
        var next = state
        var card = next.cards[wordID] ?? Scheduler.newCard(today: today)
        card.starred.toggle()
        next.cards[wordID] = card
        state = next
        persist()
    }

    // MARK: - Settings

    func setDailyNewWords(_ value: Int) { mutateSettings { $0.dailyNewWords = value } }
    func setDailyReviewCap(_ value: Int) { mutateSettings { $0.dailyReviewCap = value } }
    func setAutoPlay(_ value: Bool) { mutateSettings { $0.autoPlay = value } }
    func setHaptics(_ value: Bool) { mutateSettings { $0.haptics = value } }
    func setQuizInReview(_ value: Bool) { mutateSettings { $0.quizInReview = value } }

    func setReminder(enabled: Bool) {
        mutateSettings { $0.reminderEnabled = enabled }
        ReminderScheduler.sync(settings: state.settings)
    }

    func setReminderTime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        mutateSettings {
            $0.reminderHour = parts.hour ?? 20
            $0.reminderMinute = parts.minute ?? 30
        }
        ReminderScheduler.sync(settings: state.settings)
    }

    var reminderDate: Date {
        Calendar.current.date(
            bySettingHour: state.settings.reminderHour,
            minute: state.settings.reminderMinute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func mutateSettings(_ change: (inout Settings) -> Void) {
        var next = state
        change(&next.settings)
        next.settings.clamp()
        state = next
        persist()
    }

    // MARK: - Data

    func resetProgress() {
        var next = state
        next.cards = [:]
        next.log = StudyLog()
        next.log.rollover(to: today)
        state = next
        session = nil
        cursor = 0
        options = []
        phase = .idle
        persist()
    }

    func persistIfNeeded() { persist() }

    private func persist() {
        do {
            try repository.save(state)
        } catch {
            NSLog("LightWord: failed to save state: \(error.localizedDescription)")
        }
    }
}
