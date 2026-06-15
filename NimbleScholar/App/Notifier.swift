import Foundation
import UserNotifications
import AppKit

/// Thin wrapper over macOS user notifications. Surfaces capture problems and
/// code-release events; tapping a notification with a `url` opens it.
enum Notifier {
    private static let delegate = NotifierDelegate()

    /// Ask once (at launch) for permission and install the tap-to-open delegate.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = delegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String, url: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Shows banners while the app is foreground and opens a notification's `url` on tap.
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let urlString = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: urlString) else { return }
        await MainActor.run { NSWorkspace.shared.open(url) }
    }
}
