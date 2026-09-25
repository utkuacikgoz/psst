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
                    .font(.psst(size: 84, weight: .heavy))
                    .foregroundStyle(Color.onCanvas)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.psstCanvas.ignoresSafeArea())
                    .accessibilityHidden(true)
            case .needsName:
                if let inviter = store.invitedBy, !store.introSeen {
                    InvitedIntroView(inviter: inviter) { withAnimation { store.introSeen = true } }
                } else {
                    NameStepView()
                }
            case .needsNotificationChoice:
                NotificationStepView()
            case .ready:
                LiveHomeView()
            }
        }
        .task { await store.start() }
        // An invite link opened before onboarding (IF2). Keyed on both, since a
        // cold-start link can arrive before the phase is known.
        .task(id: "\(store.phase)|\(store.pendingInviteCode ?? "")") {
            if store.phase == .needsName, let code = store.pendingInviteCode {
                await store.prepareInvitedIntro(code: code)
            }
        }
    }
}

/// Option IF2: a newcomer's first screen is the person who invited them.
struct InvitedIntroView: View {
    let inviter: String
    let onContinue: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 70

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Space.l) {
                Text(inviter.uppercased())
                    .bandTitle(inviter, size: nameSize, tracking: Tokens.Band.titleTracking)
                    .fixedSize(horizontal: false, vertical: true)
                Text("wants to psst you")
                    .font(.psst(.title3, weight: .semibold))
                Text("First, what should \(inviter) call you?")
                    .font(.psst(.body))
                    .padding(.top, Tokens.Space.xl)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)

            PrimaryButton(title: "Continue", action: onContinue)
                .padding(Tokens.Space.xl)
        }
        .background(Color.personBand(inviter).ignoresSafeArea())
    }
}

struct LiveHomeView: View {
    @Environment(LiveStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(Personalization.self) private var personalization
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingInvite = false
    @State private var showingSettings = false
    @State private var managing: ConnectionSummary?
    @State private var confirming: ConnectionAction?
    @State private var showingPlus = false
    @State private var colouring: ConnectionSummary?
    @State private var notificationsOff = false
    @ScaledMetric(relativeTo: .largeTitle) private var firstInviteTitleSize: CGFloat = 40

    private var anySheet: Bool {
        showingInvite || showingSettings || managing != nil || confirming != nil || showingPlus || colouring != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)

            VStack(spacing: 0) {
                header.padding(.horizontal, inset)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        notices
                        if store.connections.isEmpty {
                            if store.hasLoadedConnections {
                                firstInviteBand(minHeight: Self.bandHeight(available: proxy.size.height, people: 0))
                            }
                        } else {
                            // Yo classic (H2): people and the + band share the screen
                            // equally; with many people each keeps a minimum and scrolls.
                            let bandHeight = Self.bandHeight(available: proxy.size.height, people: store.connections.count)
                            // O2: most recent first; drag a band to place it yourself.
                            ForEach(store.orderedConnections) { connection in
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
            if store.showsCoach && store.hasLoadedConnections {
                CoachOverlay { withAnimation { store.dismissCoach() } }
            }
        }
        .overlay {
            if let arrival = store.arrival {
                ArrivalView(arrival: arrival,
                            onTap: { withAnimation { store.psstBack(arrival) } },
                            onDone: { withAnimation { store.nextArrival() } },
                            color: arrival.connectionID.map {
                                personalization.color(for: $0, name: arrival.senderName)
                            })
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
        .onAppear {
            updateVisibility()
            // A code that arrived before home existed (e.g. during onboarding).
            if store.pendingInviteCode != nil { showingInvite = true }
            if store.plusRequested { showingPlus = true; store.plusRequested = false }
        }
        .onDisappear { store.isHomeVisible = false }
        .onChange(of: anySheet) { updateVisibility() }
        .onChange(of: scenePhase) { updateVisibility() }
        .onChange(of: store.plusRequested) { _, requested in
            if requested { showingPlus = true; store.plusRequested = false }
        }
        // Keep the home-screen widget's people, colours and Psst+ state current.
        .task(id: widgetSignature) {
            WidgetBridge.publish(
                WidgetBridge.people(from: store.orderedConnections) { personalization.colorHex(for: $0, name: $1) },
                unlocked: purchases.isUnlocked)
        }
        .onChange(of: store.pendingInviteCode) { _, code in
            if code != nil { showingInvite = true }
        }
        .sheet(isPresented: $showingInvite) { InviteSheet() }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .manageConnection(menuFor: $managing, confirming: $confirming)
        .sheet(isPresented: $showingPlus) { PsstPlusSheet() }
        .sheet(item: $colouring) { ColourSheet(connection: $0) }
    }

    private var widgetSignature: String {
        let people = store.orderedConnections.prefix(3)
            .map { "\($0.id)|\($0.otherName)|\(personalization.colorHex(for: $0.id, name: $0.otherName))" }
        return people.joined(separator: ",") + "|\(purchases.isUnlocked)"
    }

    /// Settings, and Psst+ beside it (PP2): always there, never in the way.
    private var settingsButton: some View {
        HStack(spacing: Tokens.Space.l) {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(minHeight: Tokens.minTouch)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Color.onCanvas)
            Text("·").foregroundStyle(Color.onCanvasSecondary).accessibilityHidden(true)
            Button {
                showingPlus = true
            } label: {
                Text("Psst+")
                    .frame(minHeight: Tokens.minTouch)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Color(hex: 0xFFD27A))
            .accessibilityHint(purchases.isUnlocked ? "Your colours, icons and sounds." : "An optional one-time unlock.")
        }
        .font(.psst(.subheadline, weight: .semibold))
        .frame(maxWidth: .infinity)
    }

    private func updateVisibility() {
        let wasVisible = store.isHomeVisible
        store.isHomeVisible = scenePhase == .active && !anySheet
        if store.isHomeVisible {
            // Re-sort by recency only as home appears, never while tapping.
            if !wasVisible { withAnimation(reduceMotion ? nil : .snappy) { store.reorderByRecency() } }
            Task { await store.showUnseenIfVisible() }
        }
    }

    private func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOff = settings.authorizationStatus == .denied
        await store.reportNotificationStatus(enabled: settings.authorizationStatus == .authorized
                                             || settings.authorizationStatus == .provisional)
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private var header: some View {
        HStack {
            Text("psst")
                .font(.psst(size: Tokens.Band.wordmarkSize, weight: .heavy)).tracking(Tokens.Band.wordmarkTracking)
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
            NoticeView(symbol: "wifi.slash", text: "Offline · taps won't get through")
        }
        if notificationsOff {
            NoticeView(symbol: "bell.slash",
                       text: "Notifications off",
                       actionTitle: "Turn on") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        if let notice = store.notice {
            NoticeView(symbol: "info.circle", text: notice, actionTitle: "OK") { store.notice = nil }
        }
    }

    /// Option E2: before anyone accepts, home is one gold band.
    private func firstInviteBand(minHeight: CGFloat) -> some View {
        Button {
            showingInvite = true
        } label: {
            VStack(spacing: Tokens.Space.m) {
                Text("INVITE YOUR FIRST PERSON")
                    .bandTitle("Invite your first person", size: firstInviteTitleSize, tracking: Tokens.Band.titleTracking)
                    .fixedSize(horizontal: false, vertical: true)
                Text("They'll appear here as a band")
                    .font(.psst(.subheadline, weight: .medium))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(Color.addBand)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Invite someone")
        .accessibilityHint("No one here yet. They'll appear here once they accept.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func row(_ connection: ConnectionSummary, minHeight: CGFloat) -> some View {
        if Self.isPaused(store.status(for: connection)) {
            // Re-read every second so the countdown moves and the band wakes up on time.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                band(connection, minHeight: minHeight, now: context.date)
            }
        } else {
            band(connection, minHeight: minHeight, now: .now)
        }
    }

    private func band(_ connection: ConnectionSummary, minHeight: CGFloat, now: Date) -> some View {
        let status = store.status(for: connection)
        return VStack(alignment: .leading, spacing: 0) {
            PersonRow(
                name: connection.otherName,
                status: Self.text(for: status, now: now),
                signal: .psst,
                effect: store.effects[connection.id],
                accessibilityHint: Self.hint(for: status, connection: connection),
                action: { store.tap(connection) },
                isBusy: Self.isBusy(status),
                statusSymbol: Self.symbol(for: status),
                minHeight: minHeight,
                cornerMark: Self.cornerMark(for: status),
                isDimmed: Self.isPaused(status),
                color: personalization.color(for: connection.id, name: connection.otherName)
            )
            // Remove, block and report: a long press here, the VoiceOver action,
            // or Settings → People. Each explains itself before acting.
            .contextMenu {
                ForEach([ConnectionAction.Kind.remove, .block, .report], id: \.self) { kind in
                    let action = ConnectionAction(kind: kind, connection: connection)
                    Button(role: kind == .remove ? nil : .destructive) {
                        confirming = action
                    } label: {
                        Label(action.menuTitle, systemImage: action.systemImage)
                    }
                }
                // Psst+ (BC1). Without Psst+ it opens the Psst+ sheet instead.
                Button {
                    if purchases.isUnlocked { colouring = connection } else { showingPlus = true }
                } label: {
                    Label("Colour…", systemImage: "paintpalette")
                }
            }
            .accessibilityAction(named: "Manage \(connection.otherName)") { managing = connection }
            .accessibilityAction(named: "Move up") { withAnimation { store.move(connection.id, by: -1) } }
            .accessibilityAction(named: "Move down") { withAnimation { store.move(connection.id, by: 1) } }
            // Hold and drag onto another band to take its place. The placed order
            // stays on this phone.
            .draggable(connection.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                withAnimation(reduceMotion ? nil : .snappy) { store.move(dragged, onto: connection.id) }
                return true
            }
        }
    }

    static func isBusy(_ status: LiveRowStatus) -> Bool {
        if case .sending = status { return true }
        return false
    }

    static func isPaused(_ status: LiveRowStatus) -> Bool {
        if case .paused = status { return true }
        return false
    }

    static func text(for status: LiveRowStatus, now: Date = .now) -> String {
        switch status {
        // Yo classic: a band shows a line only when something happened.
        case .ready, .seen, .sentEarlier: ""
        case .sending: "Sending…"
        case .sent: "Sent"
        case .notSent: "Didn't make it · tap to try again"
        case .paused(_, let until): "Try again in \(countdown(until.timeIntervalSince(now)))"
        case .received(let name, let signal): "\(name) sent a \(signal.title)"
        }
    }

    /// Settled outcomes live in the band's corner (V2).
    static func cornerMark(for status: LiveRowStatus) -> String? {
        switch status {
        case .seen: "seen"
        case .sentEarlier: "sent"
        default: nil
        }
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func symbol(for status: LiveRowStatus) -> String? {
        switch status {
        case .notSent: "exclamationmark.circle"
        case .paused: "hourglass"
        default: nil
        }
    }

    static func hint(for status: LiveRowStatus, connection: ConnectionSummary) -> String {
        switch status {
        case .notSent(let signal): "Retries \(signal.title)."
        case .paused: "Paused after several taps, so nobody gets flooded."
        case .sending: "Sending."
        default: "Sends a Psst."
        }
    }
}

/// Option B2: a full-width dark strip under the wordmark. Never a pop-up.
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
                    .font(.psst(.subheadline, weight: .bold))
                    .underline()
                    .frame(minHeight: Tokens.minTouch)
            }
        }
        .font(.psst(.subheadline, weight: .semibold))
        .foregroundStyle(Color.onCanvas)
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.s)
        .frame(maxWidth: .infinity, minHeight: Tokens.minTouch, alignment: .leading)
        .background(Color.black.opacity(0.28))
        .accessibilityElement(children: .combine)
    }
}

/// Option Y3: shown once. Any tap dismisses it without sending anything.
struct CoachOverlay: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressing = false

    var body: some View {
        Button(action: onDismiss) {
            VStack(spacing: Tokens.Space.l) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 56))
                    .scaleEffect(pressing ? 0.88 : 1)
                    .accessibilityHidden(true)
                Text("Tap a band to psst")
                    .font(.psst(.title2, weight: .heavy))
                Text("Hold to move someone or remove them")
                    .font(.psst(.body, weight: .medium))
                Text("Tap anywhere to start")
                    .font(.psst(.footnote, weight: .semibold))
                    .opacity(0.8)
                    .padding(.top, Tokens.Space.l)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.6).ignoresSafeArea())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tip: tap a band to send a Psst. Hold a band to move someone or remove them.")
        .accessibilityHint("Dismisses the tip.")
        .accessibilityAddTraits(.isButton)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.35)) { pressing = true }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeInOut(duration: 0.35)) { pressing = false }
                try? await Task.sleep(for: .milliseconds(1100))
            }
        }
    }
}
