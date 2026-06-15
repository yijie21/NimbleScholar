import Foundation
import UserNotifications

/// Thin wrapper over macOS user notifications. Used to surface capture problems
/// (e.g. metadata couldn't be fetched) even when the capture came from the browser
/// extension while the app was in the background.
enum Notifier {
    /// Ask once (at launch) for permission to post notifications. No-op if already decided.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
