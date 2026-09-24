import UIKit
import UserNotifications

/// Owns the live store so notification callbacks work even before any view appears.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let signalCategory = "SIGNAL"
    static let sendBackAction = "SEND_BACK"

    private(set) var store: LiveStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        if let testStore = UITestAPI.storeFromLaunchArguments() {
            store = testStore
            return true
        }
        #endif
        guard let config = AppConfig.live else { return true }
        store = LiveStore(api: APIClient(config: config))

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let sendBack = UNNotificationAction(identifier: Self.sendBackAction, title: "Send back", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.signalCategory, actions: [sendBack], intentIdentifiers: [])
        ])
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await store?.registerDeviceToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Signals still appear in the app; nothing else to do.
    }

    /// In the foreground on the home list, the row shows the signal instead of a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            guard let store = self.store, let payload = SignalPayload(userInfo: userInfo), store.isHomeVisible else {
                completionHandler([.banner, .list, .sound])
                return
            }
            completionHandler([])
            await store.openedNotification(payload)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let userInfo = content.userInfo
        let senderName = content.title
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            guard let store = self.store, let payload = SignalPayload(userInfo: userInfo) else { return }
            switch action {
            case Self.sendBackAction:
                if !(await store.sendBack(payload)) {
                    await Self.postSendBackFailure(to: senderName, signal: payload.signal)
                }
            case UNNotificationDefaultActionIdentifier:
                await store.openedNotification(payload)
            default:
                break
            }
        }
    }

    /// A failed background reply must not look sent.
    private static func postSendBackFailure(to name: String, signal: Signal) async {
        let content = UNMutableNotificationContent()
        content.title = "Not sent"
        content.body = "Your \(signal.title) to \(name) wasn't sent. Open Psst to try again."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
