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
                    // Keyed on the account too, so a purchase restored during onboarding is
                    // sent once there is an account; one more try shortly if it fails.
                    .task(id: PlusProof(transaction: purchases.signedTransaction, account: signedInAccount(store))) {
                        guard let proof = purchases.signedTransaction, store.api.isSignedIn else { return }
                        do {
                            try await store.api.verifyPlus(signedTransaction: proof)
                        } catch {
                            try? await Task.sleep(for: .seconds(5))
                            guard !Task.isCancelled else { return }
                            try? await store.api.verifyPlus(signedTransaction: proof)
                        }
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

    private struct PlusProof: Hashable {
        let transaction: String?
        let account: UUID?
    }

    /// The account once onboarding has made one. Reading the phase makes this view
    /// update when it changes, since the session itself isn't observed.
    @MainActor private func signedInAccount(_ store: LiveStore) -> UUID? {
        store.phase == .loading || store.phase == .needsName ? nil : store.api.accountID
    }
}
