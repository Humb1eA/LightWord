import Foundation

enum Formatting {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static func dayString(_ day: DayKey) -> String {
        dayFormatter.string(from: day.date())
    }

    static func weekdayString(_ day: DayKey) -> String {
        weekdayFormatter.string(from: day.date())
    }

    /// "今天" / "明天" / "3 天后" relative to the device's current day.
    static func dueString(_ day: DayKey) -> String {
        let delta = day.raw - DayKey.today().raw
        if delta < 0 { return "已到期" }
        if delta == 0 { return "今天" }
        if delta == 1 { return "明天" }
        return "\(delta) 天后（\(dayString(day))）"
    }
}
