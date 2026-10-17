import SwiftUI

@main
struct PsstApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var exchange = LocalExchange()
    @State private var purchases = Purchases()
    @State private var personalization = Personalization()

    var body: some Scene {
        WindowGroup {
            if let store = appDelegate.store {
                LiveRootView()
                    .environment(store)
                    .environment(purchases)
                    .environment(personalization)
                    // Invite links: https://psstapp.fun/invite/CODE (universal link) or psst://invite/CODE.
                    .onOpenURL { url in
                        if let code = InviteLink.code(from: url) {
                            store.pendingInviteCode = code
                        } else if let link = WidgetLink(url) {
                            switch link {
                            case .psst(let id): Task { await store.psstFromWidget(id) }
                            case .plus: store.plusRequested = true
                            }
                        }
                    }
                    // Tell the server about Psst+ whenever this phone has a purchase to show
                    // (launch, buy, restore), so unlimited Super Psst and your word work
                    // without first opening the Super Psst card. The server skips a fresh one.
                    .task(id: purchases.signedTransaction) {
                        guard let proof = purchases.signedTransaction, store.api.isSignedIn else { return }
                        try? await store.api.verifyPlus(signedTransaction: proof)
                    }
                    // "Offline" follows iOS's network status, not a single failed request.
                    .task {
                        for await available in NetworkWatcher.updates() {
                            store.networkPathChanged(available: available)
                        }
                    }
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        if let url = activity.webpageURL, let code = InviteLink.code(from: url) {
                            store.pendingInviteCode = code
                        }
                    }
            } else {
                // No backend configured: the labelled local preview with fictional Alex.
                HomeView()
                    .environment(exchange)
            }
        }
    }
}
