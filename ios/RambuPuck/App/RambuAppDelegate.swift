import UIKit

@MainActor
final class RambuAppDelegate: NSObject, UIApplicationDelegate {
    static var latestPushToken: String?
    static var onPushToken: ((String) -> Void)?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Self.latestPushToken = token
        Self.onPushToken?(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Notification permission and connection issues are already surfaced in the app.
        // APNs retries registration on a later launch.
    }
}
