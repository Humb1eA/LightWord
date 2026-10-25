import Foundation
import UserNotifications

/// A single repeating local notification. Local notifications need no
/// entitlement, so they survive free (7-day) sideloading.
enum ReminderScheduler {
    private static let identifier = "lightword.daily.reminder"

    static func sync(settings: Settings) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard settings.reminderEnabled else { return }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "该背单词了"
            content.body = "花五分钟，把今天的新词过一遍。"
            content.sound = .default

            var parts = DateComponents()
            parts.hour = settings.reminderHour
            parts.minute = settings.reminderMinute

            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }
}
