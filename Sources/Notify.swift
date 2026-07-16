import Foundation
import UserNotifications

/// Failure-only notifications: the app is silent when everything works.
@MainActor
enum Notify {
    private static var authorizationRequested = false

    static func failure(_ message: String) {
        NSLog("Capture failure: %@", message)
        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "Capture"
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
