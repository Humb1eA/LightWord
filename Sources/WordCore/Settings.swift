import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var dailyNewWords: Int
    public var dailyReviewCap: Int
    public var autoPlay: Bool
    public var haptics: Bool
    public var quizInReview: Bool
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int

    public init(
        dailyNewWords: Int = 10,
        dailyReviewCap: Int = 60,
        autoPlay: Bool = true,
        haptics: Bool = true,
        quizInReview: Bool = true,
        reminderEnabled: Bool = false,
        reminderHour: Int = 20,
        reminderMinute: Int = 30
    ) {
        self.dailyNewWords = dailyNewWords
        self.dailyReviewCap = dailyReviewCap
        self.autoPlay = autoPlay
        self.haptics = haptics
        self.quizInReview = quizInReview
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.clamp()
    }

    public mutating func clamp() {
        dailyNewWords = min(max(dailyNewWords, 5), 50)
        dailyReviewCap = min(max(dailyReviewCap, 10), 200)
        reminderHour = min(max(reminderHour, 0), 23)
        reminderMinute = min(max(reminderMinute, 0), 59)
    }

    public func clamped() -> Settings {
        var copy = self
        copy.clamp()
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case dailyNewWords = "new"
        case dailyReviewCap = "review"
        case autoPlay = "autoPlay"
        case haptics
        case quizInReview = "quiz"
        case reminderEnabled = "reminder"
        case reminderHour = "hour"
        case reminderMinute = "minute"
    }
}
