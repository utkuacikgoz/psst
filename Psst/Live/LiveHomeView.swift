import SwiftUI
import UserNotifications

struct LiveRootView: View {
    @Environment(LiveStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                Color.psstCanvas.ignoresSafeArea()
            case .needsName:
                NameStepView()
            case .needsNotificationChoice:
                NotificationStepView()
            case .ready:
                LiveHomeView()
            }
        }
        .task { await store.start() }
    }
}

struct LiveHomeView: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingInvite = false
    @State private var showingSettings = false
    @State private var managing: ConnectionSummary?
    @State private var notificationsOff = false

    private var anySheet: Bool { showingInvite || showingSettings || managing != nil }

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)

            VStack(spacing: 0) {
                header.padding(.horizontal, inset)

                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        notices
                        if store.connections.isEmpty {
                            if store.hasLoadedConnections { emptyState }
                        } else {
                            ForEach(store.connections) { connection in
                                row(connection)
                            }
                        }
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, Tokens.Space.l)
                }
                .refreshable { await store.refresh() }

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onCanvas)
                        .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, inset)
                .padding(.bottom, Tokens.Space.s)
            }
        }
        .background(Color.psstCanvas.ignoresSafeArea())
        .sensoryFeedback(trigger: store.latestEffect) { _, new in new?.signal.haptic }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await updateNotificationStatus()
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: LiveStore.refreshInterval)
            }
        }
        .onAppear { updateVisibility() }
        .onDisappear { store.isHomeVisible = false }
        .onChange(of: anySheet) { updateVisibility() }
        .onChange(of: scenePhase) { updateVisibility() }
        .onChange(of: store.pendingInviteCode) { _, code in
            if code != nil { showingInvite = true }
        }
        .sheet(isPresented: $showingInvite) { InviteSheet() }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .sheet(item: $managing) { ConnectionSheet(connection: $0) }
    }

    private func updateVisibility() {
        store.isHomeVisible = scenePhase == .active && !anySheet
        if store.isHomeVisible {
            Task { await store.showUnseenIfVisible() }
        }
    }

    private func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOff = settings.authorizationStatus == .denied
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private var header: some View {
        HStack {
            Text("psst")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Color.onCanvas)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingInvite = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Color.onCanvas)
                    .frame(width: Tokens.minTouch, height: Tokens.minTouch)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Invite someone")
        }
        .padding(.top, Tokens.Space.s)
    }

    @ViewBuilder private var notices: some View {
        if store.isOffline {
            NoticeView(symbol: "wifi.slash", text: "You're offline. Taps won't send until you're connected.")
        }
        if notificationsOff {
            NoticeView(symbol: "bell.slash",
                       text: "Notifications are off. Signals still show here when you open Psst.",
                       actionTitle: "Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        if let notice = store.notice {
            NoticeView(symbol: "info.circle", text: notice, actionTitle: "OK") { store.notice = nil }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text("No one here yet. Invite someone you'd like to tap.")
                .font(.body)
                .foregroundStyle(Color.onCanvas)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Invite someone") { showingInvite = true }
        }
        .padding(.top, Tokens.Space.xl)
    }

    private func row(_ connection: ConnectionSummary) -> some View {
        let status = store.status(for: connection)
        return VStack(alignment: .leading, spacing: 0) {
            PersonRow(
                name: connection.otherName,
                status: Self.text(for: status),
                signal: connection.favorite,
                effect: store.effects[connection.id],
                accessibilityHint: Self.hint(for: status, connection: connection),
                action: { store.tap(connection) },
                isBusy: Self.isBusy(status),
                statusSymbol: Self.symbol(for: status)
            )
            .accessibilityAction(named: "Choose signal") { managing = connection }

            Button {
                managing = connection
            } label: {
                HStack(spacing: Tokens.Space.s) {
                    Text("Signal: \(connection.favorite.title)")
                    Spacer(minLength: Tokens.Space.s)
                    Text("Change")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onCanvas)
                .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Signal for \(connection.otherName): \(connection.favorite.title)")
            .accessibilityHint("Choose a signal, preview it, or manage this connection.")
            .accessibilityAddTraits(.isButton)
        }
    }

    static func isBusy(_ status: LiveRowStatus) -> Bool {
        if case .sending = status { return true }
        return false
    }

    static func text(for status: LiveRowStatus) -> String {
        switch status {
        case .ready(let signal): "Tap to send \(signal.title)"
        case .sending: "Sending…"
        case .sent: "Sent"
        case .notSent: "Not sent · Retry"
        case .paused: "Paused after several taps · Retry later"
        case .seen(let signal): "\(signal.title) · seen"
        case .sentEarlier(let signal): "\(signal.title) · sent"
        case .received(let name, let signal): "\(name) sent \(signal.title)"
        }
    }

    static func symbol(for status: LiveRowStatus) -> String? {
        switch status {
        case .notSent, .paused: "exclamationmark.circle"
        default: nil
        }
    }

    static func hint(for status: LiveRowStatus, connection: ConnectionSummary) -> String {
        switch status {
        case .notSent(let signal), .paused(let signal): "Retries \(signal.title)."
        case .sending: "Sending."
        default: "Sends \(connection.favorite.title)."
        }
    }
}

/// A small, actionable explanation. Never a full-screen error.
struct NoticeView: View {
    let symbol: String
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Tokens.minTouch)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.onCanvas)
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.xs)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.controlRadius)
                .stroke(Color.onCanvasSecondary, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
