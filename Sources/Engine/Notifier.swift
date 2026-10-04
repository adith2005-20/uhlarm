import Foundation
import UserNotifications

/// Local notifications for the Wake Up Check (no push, so no paid account needed).
enum Notifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func scheduleWakeCheck(parent: UUID, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Wake Up Check"
        content.body = "Still up? Tap here and press I'm up within a minute, or the alarm rings again."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: identifier(parent), content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelWakeCheck(parent: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(parent)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(parent)])
    }

    private static func identifier(_ parent: UUID) -> String { "wake-check-\(parent.uuidString)" }
}
