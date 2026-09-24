import SwiftUI

@main
struct PsstApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var exchange = LocalExchange()

    var body: some Scene {
        WindowGroup {
            if let store = appDelegate.store {
                LiveRootView()
                    .environment(store)
                    .onOpenURL { url in
                        if let code = InviteLink.code(from: url) { store.pendingInviteCode = code }
                    }
            } else {
                // No backend configured: the labelled local preview with fictional Alex.
                HomeView()
                    .environment(exchange)
            }
        }
    }
}
