import StoreKit
import SwiftUI
import UserNotifications

struct LiveRootView: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.updateRequired {
                UpdateRequiredView()
            } else {
                phaseView
            }
        }
        // On launch and each return to the app: is this build still allowed to connect?
        .task(id: scenePhase) {
            if scenePhase == .active { await store.checkForUpdate() }
        }
    }

    @ViewBuilder private var phaseView: some View {
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

/// Forced update (owner pick, 13 Oct 2026): shown only when the server's minimum
/// build is above this one. One way forward: the App Store.
struct UpdateRequiredView: View {
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)
            VStack(alignment: .leading, spacing: 0) {
                Text("psst")
                    .font(.psst(size: Tokens.Band.wordmarkSize, weight: .heavy))
                    .tracking(Tokens.Band.wordmarkTracking)
                    .padding(.horizontal, inset)
                    .padding(.vertical, Tokens.Space.l)
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("Time for a quick update")
                            .font(.psst(size: titleSize, weight: .heavy))
                            .tracking(Tokens.Band.titleTracking)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("This version of Psst can't connect any more. The new one is free and takes a few seconds.")
                            .font(.psst(.body, weight: .medium))
                            .foregroundStyle(Color.onCanvasSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, inset)
                    .padding(.top, Tokens.Space.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { openURL(LiveStore.appStoreURL) } label: {
                    Text("UPDATE PSST")
                        .font(.psst(.title3, weight: .black))
                        .tracking(Tokens.Band.labelTracking)
                        .foregroundStyle(Color.psstCanvas)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update Psst")
                .accessibilityHint("Opens Psst in the App Store.")
            }
            .foregroundStyle(Color.onCanvas)
        }
        .background(Color.psstCanvas.ignoresSafeArea())
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
    @Environment(\.openURL) private var openURL
    @Environment(Purchases.self) private var purchases
    @Environment(Personalization.self) private var personalization
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview

    @State private var showingFeatureIntro = false
    /// The scroll area's real height, so 1–3 people fill it exactly (no stray scrolling).
    @State private var scrollHeight: CGFloat = 0
    /// How far home is pulled down past its top (2A: the cat shows, and a far enough
    /// pull refreshes), and where the list's end sits, for the cat under the + band.
    /// Only flips when a cat should show or hide, not on every scrolled point.
    @State private var topCatShowing = false
    @State private var endCatShowing = false
    @State private var pullArmed = true
    @State private var superPerson: ConnectionSummary?
    @State private var doodlePerson: ConnectionSummary?
    @AppStorage("psst.hapticsEnabled") private var hapticsEnabled = true
    @State private var showingInvite = false
    /// The empty home's gold band: straight to sharing a Psst link (2A).
    @State private var startingPsst = false
    /// A Psst link shared again from its day-5 reminder (3A).
    @State private var reshare: PsstShare?
    @State private var enteringCode = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showingSettings = false
    @State private var managing: ConnectionSummary?
    @State private var confirming: ConnectionAction?
    @State private var showingPlus = false
    @State private var colouring: ConnectionSummary?
    @State private var notificationsOff = false
    @ScaledMetric(relativeTo: .largeTitle) private var firstInviteTitleSize: CGFloat = 40

    private func loadingPeople(minHeight: CGFloat) -> some View {
        VStack(spacing: Tokens.Space.m) {
            if store.connectionsLoadFailed {
                SadCat()
                Text("Couldn't load your people.")
                Button("Try again") { Task { await store.refresh() } }
                    .frame(minHeight: Tokens.minTouch)
            } else {
                LoadingCat()
                Text(store.isOffline ? "Waiting for a connection…" : "Loading your people…")
            }
        }
        .font(.psst(.subheadline, weight: .semibold))
        .foregroundStyle(Color.onCanvas)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .accessibilityElement(children: .combine)
    }

    /// The tip waits for any full-screen moment to finish, so the two never stack.
    private var showsCoach: Bool { store.showsCoach && store.hasLoadedConnections && !anySheet && store.arrival == nil }
    private var showsDoodleTip: Bool { store.showsDoodleTip && !showsCoach && store.hasLoadedConnections && !anySheet }

    private var anySheet: Bool {
        showingFeatureIntro || superPerson != nil || doodlePerson != nil || showingInvite || startingPsst || reshare != nil || enteringCode || showingSettings || managing != nil || confirming != nil || showingPlus || colouring != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)
            // Room for the bands: the measured scroll area (an estimate only for the very
            // first frame). The gap above Settings is in the footer, so the list ends flush.
            let bottomPadding = dynamicTypeSize.isAccessibilitySize ? Tokens.Space.l : 0
            let space = scrollHeight > 0 ? scrollHeight - bottomPadding : proxy.size.height - 150

            VStack(spacing: 0) {
                header.padding(.horizontal, inset)

                ScrollViewReader { reader in
                ScrollView {
                    // Lazy: only the bands on screen are built, so hundreds of people scroll smoothly.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Pull down to search (owner pick, 13 Oct): sits just above the
                        // first band, out of view until you pull home down.
                        if showsSearch {
                            searchField(inset: inset)
                        }
                        Color.clear.frame(height: 0).id(Self.peopleAnchor)
                        // On the canvas as always, whatever colour sits behind the list.
                        notices.background(Color.psstCanvas)
                        if store.connections.isEmpty {
                            if store.hasLoadedConnections {
                                firstInviteBand(minHeight: max(Tokens.personRowMinHeight, Self.bandHeight(space: space, people: 0) - Tokens.Band.addBandMinHeight))
                                haveCodeBand
                            } else {
                                // First launch on this phone: nothing remembered yet.
                                loadingPeople(minHeight: Self.bandHeight(space: space, people: 0))
                            }
                        } else {
                            // Yo classic (H2): people share the screen above a short + band;
                            // with many people each keeps a minimum and scrolls.
                            let visible = visibleConnections
                            let bandHeight = Self.bandHeight(space: space, people: max(visible.count, 1))
                            // O2: most recent first; drag a band to place it yourself.
                            // Worked out once per render, not once per band.
                            let colours = bandColors
                            ForEach(visible) { connection in
                                row(connection, minHeight: bandHeight, colour: colours[connection.id])
                            }
                            if visible.isEmpty {
                                Text("No one called “\(searchQuery)”")
                                    .font(.psst(.body, weight: .semibold))
                                    .foregroundStyle(Color.onCanvasSecondary)
                                    .frame(maxWidth: .infinity, minHeight: Tokens.personRowMinHeight)
                            }
                            addBand(minHeight: Tokens.Band.addBandMinHeight)
                            if !dynamicTypeSize.isAccessibilitySize {
                                // 2A: push up past the end and a cat pops up in the + band's gold.
                                Color.clear.frame(height: 0)
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.scrollSpace)).minY } action: { end in
                                        let showing = end < scrollHeight - 12
                                        if showing != endCatShowing { endCatShowing = showing }
                                    }
                                    .overlay(alignment: .top) {
                                        Color.addBand.frame(height: proxy.size.height)
                                            .overlay(alignment: .top) {
                                                if endCatShowing {
                                                    PullCat(text: "Psst!", eyes: .addBand).padding(.top, Tokens.Space.m)
                                                }
                                            }
                                            .allowsHitTesting(false)
                                    }
                                    .accessibilityHidden(true)
                            }
                        }
                        if dynamicTypeSize.isAccessibilitySize { settingsButton }
                    }
                    .padding(.bottom, bottomPadding)
                    // How far the list is pulled down (2A). Measured on the stack itself: a
                    // zero-height first row doing this stopped the lazy stack building any band.
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.scrollSpace)).minY } action: { pulled($0) }
                }
                .coordinateSpace(.named(Self.scrollSpace))
                // Everyone fits: no scroll bar. Pulling down opens the gap in the first band's
                // colour, where the cat waves "I'm here!" (2A) instead of a spinner; a far
                // enough pull refreshes (see pulled(_:)).
                .scrollIndicators(Self.fits(people: store.connections.count, space: space) ? .hidden : .automatic)
                .background(alignment: .top) {
                    pullGapColour.frame(height: max(0, space / 2))
                        .overlay(alignment: .top) {
                            if topCatShowing && !store.connections.isEmpty {
                                PullCat(text: "I'm here!", eyes: showsSearch ? .psstCanvas : pullGapColour)
                                    .padding(.top, Tokens.Space.m)
                            }
                        }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
                // Start with the search field tucked above the top edge.
                .onAppear { hideSearch(reader) }
                .onChange(of: showsSearch) { hideSearch(reader) }
                .pinnedFooter(!dynamicTypeSize.isAccessibilitySize, inset: inset) { settingsButton.padding(.top, Tokens.Space.l) }
                }
            }
        }
        // Behind a sheet, an arrival or the tip, VoiceOver can't reach (and tap-send) the bands.
        .accessibilityHidden(anySheet || store.arrival != nil || showsCoach || showsDoodleTip)
        .background(Color.psstCanvas.ignoresSafeArea())
        .overlay {
            if showsCoach {
                CoachOverlay { withAnimation { store.dismissCoach() } }
            } else if showsDoodleTip {
                DoodleTipOverlay { withAnimation { store.dismissDoodleTip() } }
            }
        }
        .overlay {
            if let arrival = store.arrival {
                ArrivalView(arrival: arrival,
                            onTap: { withAnimation { store.psstBack(arrival) } },
                            onDone: { withAnimation { store.nextArrival() } },
                            color: arrival.connectionID.map {
                                Color(hex: bandColors[$0] ?? personalization.colorHex(for: $0, name: arrival.senderName))
                            },
                            onHideDoodle: { withAnimation { store.hideDoodle(arrival) } },
                            onBlock: sender(of: arrival).map { person -> () -> Void in { confirm(.block, person) } },
                            onReport: sender(of: arrival).map { person -> () -> Void in { confirm(.report, person) } })
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: store.arrival)
        .preferredColorScheme(.dark)
        .sensoryFeedback(trigger: store.latestEffect) { _, new in hapticsEnabled && store.arrival == nil ? new?.signal.haptic : nil }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Runs alongside the first refresh instead of before it.
            Task { await updateNotificationStatus() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PsstUITestLive") { await store.refresh(); return }
            #endif
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: LiveStore.refreshInterval)
            }
        }
        .onAppear {
            showFeatureIntroIfDue()
            showDesignPreviewIfRequested()
            updateVisibility()
            // A code that arrived before home existed (e.g. during onboarding).
            if store.pendingInviteCode != nil { showingInvite = true }
            if store.plusRequested { showingPlus = true; store.plusRequested = false }
        }
        .onChange(of: store.hasLoadedConnections) {
            showDesignPreviewIfRequested()
            showFeatureIntroIfDue()
        }
        .onDisappear { store.isHomeVisible = false }
        .onChange(of: anySheet) { updateVisibility() }
        .onChange(of: scenePhase) { updateVisibility() }
        // After the first accepted Psst, once its "sent" has shown and nothing
        // else is on screen. Apple decides whether the prompt actually appears.
        .task(id: store.reviewDue && store.arrival == nil && !anySheet && scenePhase == .active) {
            guard store.reviewDue, store.arrival == nil, !anySheet, scenePhase == .active else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            store.reviewDue = false
            requestReview()
        }
        .onChange(of: store.plusRequested) { _, requested in
            if requested { showingPlus = true; store.plusRequested = false }
        }
        .onChange(of: store.connections.map(\.id), initial: true) {
            personalization.assignUsualColors(to: store.connections.map { ($0.id, $0.otherName) })
        }
        // Keep the home-screen widget's people, colours and Psst+ state current.
        .task(id: widgetSignature) {
            WidgetBridge.publish(
                WidgetBridge.people(from: store.orderedConnections) { personalization.colorHex(for: $0, name: $1) },
                unlocked: purchases.isUnlocked,
                everyone: WidgetBridge.everyone(from: store.orderedConnections) { personalization.colorHex(for: $0, name: $1) })
        }
        .onChange(of: store.pendingInviteCode) { _, code in
            if code != nil { showingInvite = true }
        }
        .sheet(isPresented: $showingFeatureIntro, onDismiss: { store.dismissFeatureIntro() }) { FeatureIntroSheet() }
        .sheet(item: $superPerson) { SuperPsstSheet(connection: $0) }
        .fullScreenCover(item: $doodlePerson) { person in
            DoodleSheet(connection: person,
                        color: Color(hex: bandColors[person.id] ?? personalization.colorHex(for: person.id, name: person.otherName)))
        }
        .sheet(isPresented: $showingInvite) { InviteSheet() }
        .sheet(isPresented: $startingPsst) { InviteSheet(startPsst: true) }
        .sheet(item: $reshare) { ShareSheet(items: $0.items) }
        .task(id: store.reshareCode) {
            guard let code = store.reshareCode else { return }
            store.reshareCode = nil
            reshare = PsstShare.resend(code: code)
        }
        .sheet(isPresented: $enteringCode) { InviteSheet(startEntering: true) }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .fullScreenCover(isPresented: Binding(get: { store.showingRecap }, set: { store.showingRecap = $0 })) {
            WeeklyRecapView()
        }
        // The Sunday push can open the recap while something else is up; SwiftUI shows
        // one thing at a time, so close that first and then show the recap.
        .onChange(of: store.showingRecap) { _, show in
            guard show, anySheet else { return }
            store.showingRecap = false
            closePresentations()
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                store.showingRecap = true
            }
        }
        .manageConnection(menuFor: $managing, confirming: $confirming,
                          onSuper: { superPerson = $0 },
                          onColour: { if purchases.isUnlocked { colouring = $0 } else { showingPlus = true } },
                          onDoodle: { doodlePerson = $0 })
        .sheet(isPresented: $showingPlus) { PsstPlusSheet() }
        .sheet(item: $colouring) { ColourSheet(connection: $0) }
    }

    private func sender(of arrival: Arrival) -> ConnectionSummary? {
        store.connections.first { $0.id == arrival.connectionID }
    }

    /// Block or Report from a doodle's ••• menu (1B): the moment closes and the
    /// same confirm as holding the band asks first.
    private func confirm(_ kind: ConnectionAction.Kind, _ person: ConnectionSummary) {
        withAnimation { store.nextArrival() }
        confirming = ConnectionAction(kind: kind, connection: person)
    }

    private func closePresentations() {
        showingFeatureIntro = false
        superPerson = nil
        doodlePerson = nil
        showingInvite = false
        startingPsst = false
        reshare = nil
        enteringCode = false
        showingSettings = false
        managing = nil
        confirming = nil
        showingPlus = false
        colouring = nil
    }

    private func showDesignPreviewIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-PsstUITestLive"),
              let index = arguments.firstIndex(of: "-PsstDesignScreen"), index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "intro": showingFeatureIntro = true
        case "invite": showingInvite = true
        case "code": store.pendingInviteCode = "K7QX4MPA"; showingInvite = true
        case "activity", "settings": showingSettings = true
        case "super":
            if let person = store.connections.first(where: { $0.otherName == "Emre" }) { superPerson = person }
        default: break
        }
        #endif
    }

    /// What's new is for people who had Psst before and have someone to psst.
    private func showFeatureIntroIfDue() {
        if store.isExistingUser && !store.featureIntroSeen && store.pendingInviteCode == nil
            && !store.connections.isEmpty && !anySheet {
            showingFeatureIntro = true
        }
    }

    // MARK: Search

    /// Search appears once there are enough people to need it.
    static let searchMinimumPeople = 5
    private static let peopleAnchor = "people"

    private var showsSearch: Bool { store.connections.count >= Self.searchMinimumPeople }
    private var searchQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var visibleConnections: [ConnectionSummary] {
        guard showsSearch, !searchQuery.isEmpty else { return store.orderedConnections }
        return store.orderedConnections.filter { $0.otherName.localizedCaseInsensitiveContains(searchQuery) }
    }

    private func hideSearch(_ reader: ScrollViewProxy) {
        guard showsSearch, searchQuery.isEmpty else { return }
        DispatchQueue.main.async { reader.scrollTo(Self.peopleAnchor, anchor: .top) }
    }

    private func searchField(inset: CGFloat) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("", text: $searchText, prompt: Text("Search people").foregroundStyle(Color.onCanvasSecondary))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel("Search people")
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
                    .accessibilityLabel("Clear search")
            }
        }
        .font(.psst(.body, weight: .medium))
        .foregroundStyle(Color.onCanvas)
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: Tokens.minTouch)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: Tokens.controlRadius))
        .padding(.horizontal, inset)
        .padding(.vertical, Tokens.Space.s)
    }

    /// Home's band colours top to bottom, with no two neighbours the same.
    private var bandColors: [UUID: UInt32] {
        personalization.bandColors(for: store.orderedConnections.map { ($0.id, $0.otherName) })
    }

    private var widgetSignature: String {
        let people = store.orderedConnections
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
            .accessibilityHint(purchases.isUnlocked ? "Your word, sounds, icons and colours." : "An optional one-time unlock.")
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
        HStack { wordmark; Spacer() }.padding(.vertical, Tokens.Space.l)
    }

    private var wordmark: some View {
        Text("psst")
            .font(.psst(size: Tokens.Band.wordmarkSize, weight: .heavy))
            .tracking(Tokens.Band.wordmarkTracking)
            .foregroundStyle(Color.onCanvas)
            .accessibilityAddTraits(.isHeader)
    }

    /// Splits the scroll area between the people and the + band, but never below
    /// the band minimum. Rounded down so the stack never overflows by a fraction.
    static func bandHeight(space: CGFloat, people: Int) -> CGFloat {
        // People get the room; the + band (or "I have a code") keeps a fixed, shorter height.
        let share = (space - (people > 0 ? Tokens.Band.addBandMinHeight : 0)) / CGFloat(max(people, 1))
        return max(Tokens.personRowMinHeight, share.rounded(.down))
    }

    /// True when every band fits at its share without scrolling.
    static func fits(people: Int, space: CGFloat) -> Bool {
        CGFloat(people) * Tokens.personRowMinHeight + Tokens.Band.addBandMinHeight <= space
    }

    private var pullGapColour: Color {
        guard !showsSearch, let first = store.orderedConnections.first else { return .clear }
        return Color(hex: bandColors[first.id] ?? personalization.colorHex(for: first.id, name: first.otherName))
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
        if store.isExistingUser && store.featureIntroSeen && !store.superHintSeen && !store.connections.isEmpty {
            NoticeView(symbol: "sparkles", text: "Tap the cat on a band for Super Psst", actionTitle: "Got it") { store.dismissSuperHint() }
        }
        if store.connectionsLoadFailed && !store.connections.isEmpty {
            NoticeView(symbol: "arrow.clockwise", text: "Couldn't refresh your people", actionTitle: "Try again") {
                Task { await store.refresh() }
            }
        }
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
        // Soft update (owner pick, 13 Oct 2026): once per new version.
        if store.updateAvailable != nil {
            NoticeView(symbol: "sparkles", text: "A new Psst is ready", actionTitle: "Update",
                       action: { openURL(LiveStore.appStoreURL) },
                       onDismiss: { withAnimation { store.dismissUpdate() } })
        }
        if let notice = store.notice {
            NoticeView(symbol: "info.circle", text: notice, actionTitle: "OK") { store.notice = nil }
        }
    }

    /// Someone invited you and the App Store ate the link: enter or paste their code.
    private var haveCodeBand: some View {
        Button {
            enteringCode = true
        } label: {
            VStack(spacing: Tokens.Space.xs) {
                Text("I HAVE A CODE")
                    .font(.psst(.title3, weight: .heavy))
                    .tracking(Tokens.Band.labelTracking)
                Text("Someone invited you")
                    .font(.psst(.subheadline, weight: .medium))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.l)
            .frame(maxWidth: .infinity, minHeight: Tokens.Band.addBandMinHeight)
            .background(Color(hex: 0x5F61AE))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("I have a code")
        .accessibilityHint("Enter or paste the invite code someone sent you.")
        .accessibilityAddTraits(.isButton)
    }

    /// Option E2: before anyone accepts, home is one gold band. Since 2A (owner pick,
    /// 18 Oct 2026) it goes straight to sharing a Psst link; holding it still offers
    /// the group invite.
    private func firstInviteBand(minHeight: CGFloat) -> some View {
        Button {
            startingPsst = true
        } label: {
            VStack(spacing: Tokens.Space.m) {
                MischiefCat().frame(width: 52, height: 44)
                Text("PSST SOMEONE NEW")
                    .bandTitle("Psst someone new", size: firstInviteTitleSize, tracking: Tokens.Band.titleTracking)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your Psst is the invite.")
                    .font(.psst(.subheadline, weight: .medium))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(Color.inviteGold)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { showingInvite = true } label: { Label("Share my invite", systemImage: "person.badge.plus") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Psst someone new")
        .accessibilityHint("Shares a link with your Psst. They join when they open it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Share my invite") { showingInvite = true }
    }

    static let scrollSpace = "homeScroll"
    /// Pull this far past the top to refresh.
    static let pullToRefresh: CGFloat = 90

    /// Home's own pull to refresh (2A): the cat replaces the system spinner, which
    /// can't be hidden on one screen only. One refresh per pull; it re-arms once the
    /// list is back at rest.
    private func pulled(_ offset: CGFloat) {
        let showing = offset > 12
        if showing != topCatShowing { topCatShowing = showing }
        if offset > Self.pullToRefresh, pullArmed {
            pullArmed = false
            Task { await store.refresh() }
        } else if offset < 4, !pullArmed {
            pullArmed = true
        }
    }

    /// The effect's id when it's a Super Psst, so only those play the nudge.
    static func superEffectID(_ effect: EffectTrigger?) -> UUID? {
        effect?.signal == .superPsst ? effect?.id : nil
    }

    @ViewBuilder
    private func row(_ connection: ConnectionSummary, minHeight: CGFloat, colour: UInt32?) -> some View {
        if Self.isPaused(store.status(for: connection)) {
            // Re-read every second so the countdown moves and the band wakes up on time.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                band(connection, minHeight: minHeight, now: context.date, colour: colour)
            }
        } else {
            band(connection, minHeight: minHeight, now: .now, colour: colour)
        }
    }

    private func band(_ connection: ConnectionSummary, minHeight: CGFloat, now: Date, colour: UInt32?) -> some View {
        let status = store.status(for: connection)
        let person = PersonRow(
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
                color: Color(hex: colour ?? personalization.colorHex(for: connection.id, name: connection.otherName)),
                exchangeDate: connection.lastCreatedAt,
                exchangeFromMe: connection.lastFromMe,
                streakDays: connection.streakDays ?? 0,
                streakMoment: store.streakMoments[connection.id]
            )
            // Remove, block and report: a long press here, the VoiceOver action,
            // or Settings → People. Each explains itself before acting.
            .contextMenu {
                // 1A (owner pick): hold a band → Doodle for <name>, first in the menu.
                Button {
                    doodlePerson = connection
                } label: { Label("Doodle for \(connection.otherName)", systemImage: "scribble") }
                Button {
                    store.dismissSuperHint()
                    superPerson = connection
                } label: { Label("Super Psst…", systemImage: "sparkles") }
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
            .accessibilityAction(named: "Super Psst") { superPerson = connection }
            .accessibilityAction(named: "Doodle") { doodlePerson = connection }
            // Pull to refresh has no VoiceOver gesture since the cat replaced .refreshable.
            .accessibilityAction(named: "Refresh") { Task { await store.refresh() } }
            .accessibilityAction(named: "Manage \(connection.otherName)") { managing = connection }
            .accessibilityAction(named: "Move up") { withAnimation { store.move(connection.id, by: -1) } }
            .accessibilityAction(named: "Move down") { withAnimation { store.move(connection.id, by: 1) } }
            // ✦ (owner pick, 12 Oct): Super Psst without holding. It sits on top of
            // the band, not inside the band's button, so tapping the band still sends a Psst.
            .overlay(alignment: .bottomTrailing) {
                Button {
                    store.dismissSuperHint()
                    superPerson = connection
                } label: {
                    // The nudge mark (owner pick 1A, 14 Oct), replacing the ✦. It gives a
                    // little jump when a Super Psst goes out from this band.
                    NudgeMark(eyes: Color(hex: colour ?? personalization.colorHex(for: connection.id, name: connection.otherName)))
                        .frame(width: 48, height: 24)
                        .keyframeAnimator(initialValue: 1.0, trigger: Self.superEffectID(store.effects[connection.id])) { content, scale in
                            content.scaleEffect(reduceMotion ? 1 : CGFloat(scale))
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(1.25, duration: 0.12)
                                CubicKeyframe(1.0, duration: 0.3)
                            }
                        }
                        .frame(minWidth: Tokens.minTouch + 12, minHeight: Tokens.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(Tokens.Space.s)
                .accessibilityLabel("Super Psst for \(connection.otherName)")
            }
            // Hold and drag onto another band to take its place. The placed order
            // stays on this phone.
            .draggable(connection.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                withAnimation(reduceMotion ? nil : .snappy) { store.move(dragged, onto: connection.id) }
                return true
            }
        // At every text size the mark stays inline, in the band's corner (6A, 18 Oct 2026).
        return person
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
        case .ready, .seen, .sentEarlier, .received: ""
        case .sending: "Sending…"
        case .sent: "Sent"
        case .notSent: "Didn't make it · tap to try again"
        case .paused(_, let until): "Try again in \(countdown(until.timeIntervalSince(now)))"
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
        default: "Sends a Psst. Touch and hold for Super Psst."
        }
    }
}

/// Option B2: a full-width dark strip under the wordmark. Never a pop-up.
struct NoticeView: View {
    let symbol: String
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)? = nil

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
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .font(.psst(.subheadline, weight: .bold))
                    .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
                    .accessibilityLabel("Not now")
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
                    .font(.system(size: 56, weight: .bold))
                    .scaleEffect(pressing ? 0.88 : 1)
                    .accessibilityHidden(true)
                Text("Tap a band to psst")
                    .font(.psst(.title2, weight: .black))
                Text("Hold for Super Psst")
                    .font(.psst(.body, weight: .medium))
                Text("Tap anywhere to start")
                    .font(.psst(.footnote, weight: .semibold))
                    .foregroundStyle(Color.onCanvasSecondary)
                    .padding(.top, Tokens.Space.l)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.8).ignoresSafeArea())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tip: tap a band to send a Psst. Hold for Super Psst, colours, moving or managing people.")
        .accessibilityHint("Dismisses the tip.")
        .accessibilityAddTraits([.isButton, .isModal])
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

/// 1B (owner pick, 16 Oct 2026): doodles live in the hold menu, so a one-time tip
/// says so, in the same dark overlay as the first tip. Any tap dismisses it; it
/// never sends or opens anything.
struct DoodleTipOverlay: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressing = false

    var body: some View {
        Button(action: onDismiss) {
            VStack(spacing: Tokens.Space.l) {
                Image(systemName: "scribble")
                    .font(.system(size: 56, weight: .bold))
                    .scaleEffect(pressing ? 0.88 : 1)
                    .accessibilityHidden(true)
                Text("Hold a band to doodle")
                    .font(.psst(.title2, weight: .black))
                Text("Draw them something for their widget.")
                    .font(.psst(.body, weight: .medium))
                Text("Tap anywhere to start")
                    .font(.psst(.footnote, weight: .semibold))
                    .foregroundStyle(Color.onCanvasSecondary)
                    .padding(.top, Tokens.Space.l)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.8).ignoresSafeArea())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New: hold a band, or use the Doodle action, to draw someone a doodle for their widget.")
        .accessibilityHint("Dismisses the tip.")
        .accessibilityAddTraits([.isButton, .isModal])
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
