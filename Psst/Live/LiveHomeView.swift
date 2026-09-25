import SwiftUI
import UserNotifications

struct LiveRootView: View {
    @Environment(LiveStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                // Matches the launch screen, so startup has no visible jump.
                Text("psst")
                    .font(.system(size: 84, weight: .heavy))
                    .foregroundStyle(Color.onCanvas)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.psstCanvas.ignoresSafeArea())
                    .accessibilityHidden(true)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    VStack(alignment: .leading, spacing: 0) {
                        notices.padding(.horizontal, inset)
                        if store.connections.isEmpty {
                            if store.hasLoadedConnections {
                                emptyState
                                addBand(minHeight: Tokens.personRowMinHeight)
                            }
                        } else {
                            // Yo classic (H2): people and the + band share the screen
                            // equally; with many people each keeps a minimum and scrolls.
                            let bandHeight = Self.bandHeight(available: proxy.size.height, people: store.connections.count)
                            ForEach(store.connections) { connection in
                                row(connection, minHeight: bandHeight)
                            }
                            addBand(minHeight: bandHeight)
                        }
                        if dynamicTypeSize.isAccessibilitySize { settingsButton }
                    }
                    .padding(.bottom, Tokens.Space.l)
                }
                .refreshable { await store.refresh() }
                .pinnedFooter(!dynamicTypeSize.isAccessibilitySize, inset: inset) { settingsButton }
            }
        }
        .background(Color.psstCanvas.ignoresSafeArea())
        .overlay {
            if let arrival = store.arrival {
                ArrivalView(arrival: arrival,
                            onTap: { withAnimation { store.psstBack(arrival) } },
                            onDone: { withAnimation { store.arrival = nil } })
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: store.arrival)
        .preferredColorScheme(.dark)
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

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onCanvas)
                .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
                .contentShape(Rectangle())
        }
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
                .font(.system(size: Tokens.Band.wordmarkSize, weight: .heavy)).tracking(Tokens.Band.wordmarkTracking)
                .foregroundStyle(Color.onCanvas)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.vertical, Tokens.Space.l)
    }

    /// Splits the space below the header and above Settings between the people
    /// and the + band, but never below the band minimum.
    static func bandHeight(available: CGFloat, people: Int) -> CGFloat {
        let chrome: CGFloat = 150 // header and Settings footer, approximately
        let share = (available - chrome) / CGFloat(people + 1)
        return max(Tokens.personRowMinHeight, share)
    }

    /// The gold + band that ends the list, as in Yo. Opens the invite sheet.
    private func addBand(minHeight: CGFloat) -> some View {
        Button {
            showingInvite = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: Tokens.Band.wordmarkSize, weight: .light))
                .foregroundStyle(Color.onCanvas)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(Color.addBand)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Invite someone")
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
        }
        .padding(.vertical, Tokens.Space.xl)
        .padding(.horizontal, Tokens.Space.xl)
    }

    private func row(_ connection: ConnectionSummary, minHeight: CGFloat) -> some View {
        let status = store.status(for: connection)
        return VStack(alignment: .leading, spacing: 0) {
            PersonRow(
                name: connection.otherName,
                status: Self.text(for: status),
                signal: .psst,
                effect: store.effects[connection.id],
                accessibilityHint: Self.hint(for: status, connection: connection),
                action: { store.tap(connection) },
                isBusy: Self.isBusy(status),
                statusSymbol: Self.symbol(for: status),
                minHeight: minHeight
            )
            // Remove and block live in a separate sheet: from here by long press or
            // the VoiceOver action, and always from Settings → People.
            .contextMenu {
                Button("Manage \(connection.otherName)…", systemImage: "person.crop.circle") { managing = connection }
            }
            .accessibilityAction(named: "Manage \(connection.otherName)") { managing = connection }
        }
    }

    static func isBusy(_ status: LiveRowStatus) -> Bool {
        if case .sending = status { return true }
        return false
    }

    static func text(for status: LiveRowStatus) -> String {
        switch status {
        // Yo classic: a band shows a line only when something happened.
        case .ready: ""
        case .sending: "Sending…"
        case .sent: "Sent"
        case .notSent: "Not sent · Retry"
        case .paused: "Paused after several taps · Retry later"
        case .seen(let signal): "\(signal.title) · seen"
        case .sentEarlier(let signal): "\(signal.title) · sent"
        case .received(let name, let signal): "\(name) sent a \(signal.title)"
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
        default: "Sends a Psst."
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
