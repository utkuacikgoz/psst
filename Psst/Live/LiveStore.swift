import Foundation
import Observation

/// What a person row may truthfully say. Mirrors DESIGN.md "Send feedback must be truthful".
enum LiveRowStatus: Equatable {
    case ready(Signal)
    case sending(Signal)
    /// The server accepted and stored it. Not proof the other phone showed it.
    case sent(Signal)
    case notSent(Signal)
    /// The server's pacing limit; tapping works again at `until`.
    case paused(Signal, until: Date)
    /// Their app reported displaying it.
    case seen(Signal)
    /// Stored on the server; no display report from them yet.
    case sentEarlier(Signal)
    case received(from: String, Signal)
}

enum SendFailure: Equatable {
    case retry
    case rateLimited
}

enum SendState: Equatable {
    case sending(eventID: UUID, signal: Signal)
    case sent(eventID: UUID, signal: Signal)
    case failed(eventID: UUID, signal: Signal, reason: SendFailure)
}

@MainActor
@Observable
final class LiveStore {
    enum Phase: Equatable {
        case loading
        case needsName
        case needsNotificationChoice
        case ready
    }

    static let minimumTapInterval: TimeInterval = 0.8
    static let refreshInterval: Duration = .seconds(15)
    /// The server allows 10 per rolling minute to one person, so a slot is free within a minute.
    static let pauseDuration: TimeInterval = 60
    static let welcomedKey = "psst.live.welcomedConnections"
    static let pinnedOrderKey = "psst.live.pinnedOrder"
    static let featureIntroKey = "psst.live.featureIntro.202610"
    static let superHintKey = "psst.live.superHint.202610"
    private(set) var featureIntroSeen = false
    private(set) var superHintSeen = false
    private(set) var isExistingUser = false

    static let coachKey = "psst.live.coachShown"
    static let reviewAskedKey = "psst.live.reviewAsked"
    static let myNameKey = "psst.live.myName"
    /// The last list of people from the server, shown at launch while it refreshes.
    static let connectionsCacheKey = "psst.live.connectionsCache"
    /// The last leaderboard, so it opens instantly and survives a failed refresh.
    static let activityCacheKey = "psst.live.activityCache"

    private(set) var phase: Phase = .loading
    /// Your own name as last saved on this phone (ED1). Nil on installs from
    /// before it was kept; Settings then asks you to add it.
    private(set) var myName: String?
    private(set) var connections: [ConnectionSummary] = [] { didSet { reorder() } }
    private(set) var sendStates: [UUID: SendState] = [:]
    /// The effect currently playing on each row, keyed by connection. A new event ID replays it.
    private(set) var effects: [UUID: EffectTrigger] = [:]
    /// The most recent effect anywhere, for a single haptic per event.
    private(set) var latestEffect: EffectTrigger?
    /// A Psst that just arrived, shown full screen for a moment (R2).
    var arrival: Arrival? {
        didSet {
            if let arrival, arrival.id != oldValue?.id { arrivalShown(arrival) }
        }
    }
    /// A sender's unseen Pssts, reported seen only once their moment is on screen.
    @ObservationIgnored private var pendingAcks: [UUID: [UUID]] = [:]
    /// Moments already shown, so a failed "seen" report doesn't replay them.
    @ObservationIgnored private var displayed: Set<UUID> = []
    @ObservationIgnored private var ackTask: Task<Void, Never>?
    /// MA2: the senders still to show, oldest first, so the newest comes last.
    private(set) var arrivalQueue: [Arrival] = []
    /// Shown as "Offline" on home. True only when iOS says there's no network, or
    /// two requests in a row couldn't reach the server: one blip (a network handoff,
    /// the first request after coming back to the app) isn't being offline.
    private(set) var isOffline = false
    private(set) var networkAvailable = true
    @ObservationIgnored private var failedInARow = 0
    private(set) var hasLoadedConnections = false
    /// The private leaderboard, last known first; refreshActivity() replaces it.
    private(set) var activity: [ActivitySummary] = []
    private(set) var connectionsLoadFailed = false
    /// A short, factual message for the home screen (e.g. a connection that ended).
    var notice: String?
    /// Set from an invite link (https://psstapp.fun/invite/CODE or psst://invite/CODE); the home screen opens the invite sheet with it.
    var pendingInviteCode: String?
    /// IF2: someone new opened an invite link. Their start leads with the
    /// inviter; once they've chosen a name, the invite is accepted for them.
    private(set) var invitedBy: String?
    private(set) var introInviteCode: String?
    var introSeen = false
    /// Set by the widget's Psst+ message (psst://plus); home opens Psst+.
    var plusRequested = false
    /// Set once, after the first Psst the server accepts; home then shows
    /// Apple's rating prompt (which Apple may still choose not to show).
    var reviewDue = false
    /// True only while the home list is on screen in the foreground. Signals are
    /// acknowledged as seen only then, because only then were they displayed.
    var isHomeVisible = false

    let api: PsstAPI
    private let defaults: UserDefaults
    private let now: () -> Date
    private let sentDisplayDuration: Duration
    private let sendBackRetryDelay: Duration
    @ObservationIgnored private var lastTapAt: [UUID: Date] = [:]
    private var pausedUntil: [UUID: Date] = [:]
    /// People the user placed by dragging, top first. Kept on this device only.
    private(set) var pinnedOrder: [UUID] = [] { didSet { reorder() } }
    /// Everyone else, most recent first, as of the last time home appeared. Not
    /// re-sorted while you're tapping, so a band never moves under your finger.
    private var recencyOrder: [UUID] = [] { didSet { reorder() } }
    @ObservationIgnored private var lastRegisteredToken: String?
    @ObservationIgnored private var pendingDeviceToken: String?
    @ObservationIgnored private var registeringToken = false
    @ObservationIgnored private var tokenRetryAt = Date.distantPast
    @ObservationIgnored private var tokenFailures = 0
    @ObservationIgnored private var accountGeneration = 0

    static let profileKey = "psst.live.profileCreated"
    /// Screenshot runs never show the rating prompt.
    static let isUITest = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-PsstUITest") }
    static let notificationChoiceKey = "psst.live.notificationChoiceMade"

    init(api: PsstAPI, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         sentDisplayDuration: Duration = .seconds(2), sendBackRetryDelay: Duration = .seconds(2)) {
        self.api = api
        self.sendBackRetryDelay = sendBackRetryDelay
        self.defaults = defaults
        self.now = now
        self.sentDisplayDuration = sentDisplayDuration
        isExistingUser = api.isSignedIn && defaults.bool(forKey: Self.profileKey)
        featureIntroSeen = defaults.bool(forKey: Self.featureIntroKey)
        superHintSeen = defaults.bool(forKey: Self.superHintKey)
        coachDismissed = defaults.bool(forKey: Self.coachKey)
        myName = defaults.string(forKey: Self.myNameKey)
        pinnedOrder = (defaults.stringArray(forKey: Self.pinnedOrderKey) ?? []).compactMap(UUID.init(uuidString:))
        // Show the people from last time straight away; refresh() replaces them.
        if defaults.bool(forKey: Self.profileKey),
           let data = defaults.data(forKey: Self.connectionsCacheKey),
           let cached = try? JSONDecoder().decode([ConnectionSummary].self, from: data) {
            connections = cached
            reorderByRecency()
        }
        reorder()
        if let data = defaults.data(forKey: Self.activityCacheKey),
           let cached = try? JSONDecoder().decode([ActivitySummary].self, from: data) {
            activity = cached
        }
    }

    /// Fetches the leaderboard and keeps it for next time. On failure the last
    /// known one stays, and the error tells the screen to offer Try again.
    func refreshActivity() async throws {
        let monthStart = Calendar.current.dateInterval(of: .month, for: now())?.start ?? now()
        let rows = try await api.activity(monthStart: monthStart)
        activity = rows
        if let data = try? JSONEncoder().encode(rows) { defaults.set(data, forKey: Self.activityCacheKey) }
    }

    // MARK: Onboarding

    func start() async {
        guard api.isSignedIn, defaults.bool(forKey: Self.profileKey) else {
            phase = .needsName
            return
        }
        phase = defaults.bool(forKey: Self.notificationChoiceKey) ? .ready : .needsNotificationChoice
        await refresh()
    }

    /// Creates the anonymous account if needed, then saves the name.
    func createProfile(name: String) async throws {
        if !api.isSignedIn {
            try await api.signUpAnonymously()
        }
        try await api.setDisplayName(name)
        remember(name: name)
        defaults.set(true, forKey: Self.profileKey)
        phase = defaults.bool(forKey: Self.notificationChoiceKey) ? .ready : .needsNotificationChoice
        await acceptIntroInvite()
    }

    func finishNotificationChoice() {
        defaults.set(true, forKey: Self.notificationChoiceKey)
        phase = .ready
        Task { await acceptIntroInvite() }
    }

    /// Looks up an invite link opened before onboarding. Only a usable invite
    /// gets the intro; anything else waits for the invite sheet to explain it.
    func prepareInvitedIntro(code: String) async {
        guard phase == .needsName, introInviteCode != code else { return }
        do {
            if !api.isSignedIn { try await api.signUpAnonymously() }
            let preview = try await api.previewInvite(code: code)
            guard preview.status == .pending, let name = preview.inviterName else { return }
            invitedBy = name
            introInviteCode = code
            pendingInviteCode = nil
        } catch {
            // Keep the code; the invite sheet will try again after onboarding.
        }
    }

    /// Accepts the intro's invite once onboarding is done. If it can't be
    /// accepted any more, the invite sheet opens to say why.
    func acceptIntroInvite() async {
        guard phase == .ready, let code = introInviteCode else { return }
        introInviteCode = nil
        invitedBy = nil
        // Make sure the inviter counts as new, so their welcome (J2) plays.
        if defaults.stringArray(forKey: Self.welcomedKey) == nil {
            defaults.set(connections.map(\.id.uuidString), forKey: Self.welcomedKey)
        }
        do {
            _ = try await acceptInvite(code: code)
        } catch {
            pendingInviteCode = code
        }
    }

    func rename(to name: String) async throws {
        try await api.setDisplayName(name)
        remember(name: name)
    }

    private func remember(name: String) {
        myName = name
        defaults.set(name, forKey: Self.myNameKey)
    }

    // MARK: App version

    /// Below the server's minimum build: Psst asks for an update and nothing else.
    private(set) var updateRequired = false
    /// A newer version is out (its version text), until dismissed for that build.
    private(set) var updateAvailable: String?
    @ObservationIgnored private var latestBuild = 0
    @ObservationIgnored private var reportedVersion = false
    static let updateDismissedKey = "psst.updateDismissedBuild"
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6815764359")!

    nonisolated static var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }
    nonisolated static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// Compares this build with the server's requirements, and reports the version
    /// once per launch. If the server can't be reached, nothing changes: an
    /// unreachable check never locks anyone out.
    func checkForUpdate(build: Int = LiveStore.currentBuild, version: String = LiveStore.currentVersion) async {
        guard build > 0, let requirements = try? await api.appRequirements() else { return }
        updateRequired = build < requirements.minBuild
        latestBuild = requirements.latestBuild
        let dismissed = defaults.integer(forKey: Self.updateDismissedKey)
        updateAvailable = requirements.latestBuild > build && requirements.latestBuild > dismissed
            ? (requirements.latestVersion ?? "") : nil
        if api.isSignedIn, defaults.bool(forKey: Self.profileKey), !reportedVersion {
            reportedVersion = (try? await api.reportAppVersion(version, build: build)) != nil
        }
    }

    func dismissUpdate() {
        defaults.set(latestBuild, forKey: Self.updateDismissedKey)
        updateAvailable = nil
    }

    // MARK: Reachability

    /// iOS's own network status (NWPathMonitor, wired in PsstApp).
    func networkPathChanged(available: Bool) {
        networkAvailable = available
        if available {
            failedInARow = 0
            if isOffline {
                isOffline = false
                tokenRetryAt = .distantPast
                Task { await refresh() }
            }
        } else {
            isOffline = true
        }
    }

    private func noteReachable() {
        failedInARow = 0
        isOffline = false
    }

    private func noteUnreachable() {
        failedInARow += 1
        isOffline = !networkAvailable || failedInARow >= 2
    }

    // MARK: Loading

    /// Loads the people from the server. Calls that overlap (launch, foregrounding,
    /// pull to refresh) share one request instead of each making their own.
    func refresh() async {
        if let inFlight = refreshTask { return await inFlight.value }
        let task = Task { await load() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    // MARK: Doodles on the widget (2A, 4A, 5A)

    /// Puts the newest unanswered doodle on the widget (free, Psst+ or not), and
    /// takes it off once you've pssted that person back.
    /// "Hide doodle" (1B): off your widget without pssting back.
    func hideDoodle(_ arrival: Arrival) {
        WidgetBridge.hideDoodle(eventID: arrival.id)
        nextArrival()
    }

    func publishDoodle() async {
        do { WidgetBridge.publishDoodle(try await api.latestDoodle()) } catch {}
    }

    // MARK: Streaks (3A)

    /// "7 days in a row" shows on a band for a moment when its streak grows (3+).
    private(set) var streakMoments: [UUID: Int] = [:]
    @ObservationIgnored private var reportedTimeZone: String?
    static let streakMomentDuration: Duration = .seconds(3)

    private func noteStreaks(from old: [ConnectionSummary], to new: [ConnectionSummary]) {
        let before = Dictionary(old.map { ($0.id, $0.streakDays ?? 0) }, uniquingKeysWith: { first, _ in first })
        for connection in new {
            let days = connection.streakDays ?? 0
            guard days >= 3, let previous = before[connection.id], days > previous else { continue }
            streakMoments[connection.id] = days
            Task { [weak self] in
                try? await Task.sleep(for: Self.streakMomentDuration)
                if self?.streakMoments[connection.id] == days { self?.streakMoments[connection.id] = nil }
            }
        }
    }

    // MARK: Weekly recap (4A; on from the start since owner pick 2A, 16 Oct 2026)

    /// On or off on the server; nil until known. On unless you turned it off.
    private(set) var recapEnabled: Bool?
    /// The recap sheet, opened from the Sunday push.
    var showingRecap = false
    @ObservationIgnored private var loadedRecapStatus = false

    private func loadRecapStatus() async {
        guard !loadedRecapStatus, let status = try? await api.weeklyRecapStatus() else { return }
        loadedRecapStatus = true
        recapEnabled = status.enabled
    }

    /// Turns the recap on or off. Returns false if the server didn't take it.
    @discardableResult
    func setWeeklyRecap(_ enabled: Bool) async -> Bool {
        do {
            try await api.setWeeklyRecap(enabled)
            recapEnabled = enabled
            return true
        } catch {
            return false
        }
    }

    /// A day is the person's own day, so the server keeps the phone's time zone. Once per
    /// launch, and again if it changes (travel).
    private func reportTimeZone() async {
        let zone = TimeZone.current.identifier
        guard zone != reportedTimeZone else { return }
        if (try? await api.setTimeZone(zone)) != nil { reportedTimeZone = zone }
    }

    private func load() async {
        do {
            let latest = try await api.listConnections()
            // Unchanged polls leave the list alone, so home doesn't redraw and the cache isn't rewritten.
            if latest != connections {
                noteStreaks(from: connections, to: latest)
                connections = latest
                if let data = try? JSONEncoder().encode(latest) {
                    defaults.set(data, forKey: Self.connectionsCacheKey)
                }
            }
            if !hasLoadedConnections { reorderByRecency() }
            hasLoadedConnections = true
            connectionsLoadFailed = false
            noteReachable()
            await retryDeviceToken()
            await reportTimeZone()
            await loadRecapStatus()
            await showUnseenIfVisible()
            await publishDoodle()
        } catch APIError.offline {
            connectionsLoadFailed = true
            noteUnreachable()
        } catch APIError.signedOut {
            resetLocalAccount()
        } catch {
            connectionsLoadFailed = true
            // Preserve the cached list while showing that it could not refresh.
        }
    }

    /// Plays each connection's newest unseen signal on its row, then reports them seen.
    /// Then welcomes anyone new.
    /// Overlapping calls (first load and home appearing) share one request.
    func showUnseenIfVisible() async {
        guard isHomeVisible else { return welcomeNewConnections() }
        if let inFlight = unseenTask { return await inFlight.value }
        let task = Task {
            if isHomeVisible, let unseen = try? await api.listUnseen(), !unseen.isEmpty { await show(unseen) }
            welcomeNewConnections()
        }
        unseenTask = task
        await task.value
        unseenTask = nil
    }

    @ObservationIgnored private var unseenTask: Task<Void, Never>?

    /// Option J2: a person who just became tappable gets a full-screen welcome,
    /// once, while home is on screen. People already there on first launch don't.
    func welcomeNewConnections() {
        guard hasLoadedConnections else { return }
        let ids = connections.map(\.id.uuidString)
        guard var welcomed = defaults.stringArray(forKey: Self.welcomedKey).map(Set.init) else {
            defaults.set(ids, forKey: Self.welcomedKey)
            return
        }
        // Anyone who already exchanged a signal needs no welcome.
        for connection in connections where connection.lastEventId != nil {
            welcomed.insert(connection.id.uuidString)
        }
        if isHomeVisible, arrival == nil,
           let new = connections.last(where: { !welcomed.contains($0.id.uuidString) }) {
            welcomed.insert(new.id.uuidString)
            arrival = Arrival(id: new.id, connectionID: new.id, senderName: new.otherName, kind: .joined)
        }
        defaults.set(Array(welcomed), forKey: Self.welcomedKey)
    }

    private func show(_ unseen: [UnseenSignal]) async {
        var newest: [UUID: UnseenSignal] = [:]
        for signal in unseen where newest[signal.connectionId].map({ signal.createdAt > $0.createdAt }) ?? true {
            newest[signal.connectionId] = signal
        }
        for (connectionID, signal) in newest where connections.contains(where: { $0.id == connectionID }) {
            play(EffectTrigger(id: signal.id, signal: signal.signal), on: connectionID)
        }
        // MA2: one full-screen moment per sender, one after another, newest last.
        let senders = newest.values
            .filter { s in connections.contains { $0.id == s.connectionId } }
            .sorted { $0.createdAt < $1.createdAt }
        let many = senders.count > 1
        let moments = senders.enumerated().map { index, s in
            Arrival(id: s.id, connectionID: s.connectionId, senderName: s.senderName,
                    kind: s.signal == .superPsst ? .superPsst : s.signal == .doodle ? .doodle : (s.sameMoment == true ? .sameMoment : .signal),
                    doodle: s.doodle,
                    position: many ? index + 1 : nil, total: many ? senders.count : nil,
                    note: heldPsstConnections.remove(s.connectionId) == nil ? nil
                        : "Sent \(PersonRow.lowercasedStart(ExchangeTime.label(s.createdAt, now: now()))), before you had Psst")
        }
        // "Seen" is reported when each sender's moment is actually on screen, not
        // when it's queued: three senders at once aren't all seen in the first second.
        for sender in senders {
            pendingAcks[sender.id] = unseen.filter { $0.connectionId == sender.connectionId }.map(\.id)
        }
        // Already shown (its "seen" report failed): report it now, don't show it twice.
        let alreadyShown = moments.filter { displayed.contains($0.id) }
        for moment in alreadyShown {
            if let ids = pendingAcks.removeValue(forKey: moment.id) { await ack(ids) }
        }
        let waiting = Set(arrivalQueue.map(\.id) + [arrival?.id].compactMap { $0 })
        let fresh = moments.filter { !displayed.contains($0.id) && !waiting.contains($0.id) }
        if arrival == nil, let first = fresh.first {
            arrival = first
            arrivalQueue = Array(fresh.dropFirst())
        } else {
            arrivalQueue += fresh
        }
        await ackTask?.value
    }

    private func arrivalShown(_ shown: Arrival) {
        displayed.insert(shown.id)
        guard let ids = pendingAcks.removeValue(forKey: shown.id) else { return }
        ackTask = Task { await ack(ids) }
    }

    /// Waits for the latest "seen" report (tests).
    func waitForAcks() async { await ackTask?.value }

    private func ack(_ ids: [UUID]) async {
        if (try? await api.ackSignals(ids)) != nil, let updated = try? await api.listConnections(),
           updated != connections {
            connections = updated
        }
    }

    private func play(_ trigger: EffectTrigger, on connectionID: UUID) {
        effects[connectionID] = trigger
        latestEffect = trigger
    }

    // MARK: Tap-and-hold tip (Y3)

    /// Shown once, over home, the first time there's someone to tap and no
    /// full-screen moment is playing.
    var showsCoach: Bool {
        !coachDismissed && !connections.isEmpty && arrival == nil
    }

    private(set) var coachDismissed = false

    func dismissFeatureIntro() {
        featureIntroSeen = true
        defaults.set(true, forKey: Self.featureIntroKey)
    }

    func dismissSuperHint() {
        superHintSeen = true
        defaults.set(true, forKey: Self.superHintKey)
    }

    func dismissCoach() {
        if !isExistingUser { dismissSuperHint(); dismissFeatureIntro() }
        coachDismissed = true
        defaults.set(true, forKey: Self.coachKey)
    }

    // MARK: Order (O2, plus dragging)

    /// Pinned people first in the order placed, then new people, then everyone
    /// else most recent first.
    /// Worked out when the people or their order change, not on every read, so a
    /// long list isn't re-sorted each time home redraws.
    private(set) var orderedConnections: [ConnectionSummary] = []

    private func reorder() {
        let byID = Dictionary(connections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pinnedIDs = Set(pinnedOrder)
        let pinned = pinnedOrder.compactMap { byID[$0] }
        let known = recencyOrder.filter { byID[$0] != nil && !pinnedIDs.contains($0) }
        let knownIDs = Set(known)
        let new = Self.byRecency(connections.filter { !pinnedIDs.contains($0.id) && !knownIDs.contains($0.id) })
        orderedConnections = pinned + new + known.compactMap { byID[$0] }
    }

    /// Called when home appears, never mid-tapping.
    func reorderByRecency() {
        recencyOrder = Self.byRecency(connections).map(\.id)
    }

    static func byRecency(_ list: [ConnectionSummary]) -> [ConnectionSummary] {
        list.sorted { a, b in
            let (x, y) = (a.lastCreatedAt ?? .distantPast, b.lastCreatedAt ?? .distantPast)
            return x != y ? x > y : a.otherName.localizedStandardCompare(b.otherName) == .orderedAscending
        }
    }

    /// Dropping one band onto another takes that band's place. The moved person,
    /// and everyone above the lowest placed person, stays where they are.
    func move(_ id: UUID, onto target: UUID) {
        var ids = orderedConnections.map(\.id)
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        let placed = Set(pinnedOrder).union([id])
        let lowest = ids.lastIndex { placed.contains($0) } ?? to
        pinnedOrder = Array(ids.prefix(through: lowest))
        defaults.set(pinnedOrder.map(\.uuidString), forKey: Self.pinnedOrderKey)
    }

    /// VoiceOver's Move up / Move down.
    func move(_ id: UUID, by offset: Int) {
        let ids = orderedConnections.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        move(id, onto: ids[index + offset])
    }

    func resetOrder() {
        pinnedOrder = []
        defaults.removeObject(forKey: Self.pinnedOrderKey)
        defaults.removeObject(forKey: Self.coachKey)
        coachDismissed = false
        reorderByRecency()
    }

    // MARK: Sending

    func status(for connection: ConnectionSummary) -> LiveRowStatus {
        switch sendStates[connection.id] {
        case .sending(_, let signal): return .sending(signal)
        case .sent(_, let signal): return .sent(signal)
        case .failed(_, let signal, .retry): return .notSent(signal)
        case .failed(_, let signal, .rateLimited):
            if let until = pausedUntil[connection.id], until > now() { return .paused(signal, until: until) }
        case nil: break
        }
        guard let last = connection.lastSignal, let fromMe = connection.lastFromMe else {
            return .ready(.psst)
        }
        if !fromMe { return .received(from: connection.otherName, last) }
        return connection.lastSeenAt == nil ? .sentEarlier(last) : .seen(last)
    }

    /// The row tap. Ignored while a send is in flight; a failed send is retried
    /// with its original event ID so the server can't store it twice.
    @discardableResult
    func tap(_ connection: ConnectionSummary) -> Task<Void, Never>? {
        let id = connection.id
        switch sendStates[id] {
        case .sending:
            return nil
        case .failed(let eventID, let signal, let reason):
            if reason == .rateLimited, let until = pausedUntil[id], until > now() { return nil }
            lastTapAt[id] = now()
            return Task { await send(connectionID: id, eventID: eventID, signal: signal) }
        case .sent, nil:
            if let last = lastTapAt[id], now().timeIntervalSince(last) < Self.minimumTapInterval {
                return nil
            }
            lastTapAt[id] = now()
            return Task { await send(connectionID: id, eventID: UUID(), signal: .psst) }
        }
    }

    @discardableResult
    func sendSuper(_ connection: ConnectionSummary) -> Task<Void, Never>? {
        // A pending/failed send must be resolved first; never replace its retry ID.
        guard sendStates[connection.id] == nil || {
            if case .sent = sendStates[connection.id] { return true }; return false
        }() else { return nil }
        if let until = pausedUntil[connection.id], until > now() { return nil }
        let eventID = UUID()
        sendStates[connection.id] = .sending(eventID: eventID, signal: .superPsst)
        return Task { await send(connectionID: connection.id, eventID: eventID, signal: .superPsst) }
    }

    /// A doodle (1A): sent like a Super Psst, with its strokes kept for a retry.
    /// nil when nothing was sent (a send to them is still going, or they're paused):
    /// the pad stays open so the drawing isn't lost. It may replace a failed send.
    @discardableResult
    func sendDoodle(_ connection: ConnectionSummary, strokes: DoodleStrokes) -> Task<Void, Never>? {
        guard !strokes.isEmpty, sendStates[connection.id] == nil || {
            switch sendStates[connection.id] {
            case .sent, .failed: return true
            default: return false
            }
        }() else { return nil }
        if let until = pausedUntil[connection.id], until > now() { return nil }
        if case .failed(let failedID, .doodle, _) = sendStates[connection.id] { doodleStrokes[failedID] = nil }
        let eventID = UUID()
        doodleStrokes[eventID] = strokes
        sendStates[connection.id] = .sending(eventID: eventID, signal: .doodle)
        return Task { await send(connectionID: connection.id, eventID: eventID, signal: .doodle) }
    }

    /// Strokes of doodles not yet accepted, so a retry sends the same drawing.
    @ObservationIgnored private var doodleStrokes: [UUID: DoodleStrokes] = [:]

    func send(connectionID: UUID, eventID: UUID, signal: Signal) async {
        sendStates[connectionID] = .sending(eventID: eventID, signal: signal)
        do {
            let result: SendResult
            if signal == .doodle, let strokes = doodleStrokes[eventID] {
                result = try await api.sendDoodle(eventID: eventID, connectionID: connectionID, strokes: strokes)
                doodleStrokes[eventID] = nil
            } else {
                result = try await api.sendSignal(eventID: eventID, connectionID: connectionID, signal: signal == .doodle ? .psst : signal)
            }
            noteReachable()
            // Acceptance includes the authoritative timestamp, even if the
            // subsequent list refresh fails. Never synthesize a sent time.
            connections = connections.map { connection in
                guard connection.id == connectionID,
                      connection.lastCreatedAt.map({ $0 <= result.createdAt }) ?? true else { return connection }
                return ConnectionSummary(connectionId: connection.id, otherId: connection.otherId,
                    otherName: connection.otherName, lastEventId: result.id, lastFromMe: true,
                    lastEffect: signal.rawValue, lastCreatedAt: result.createdAt, lastSeenAt: nil,
                    unseenCount: connection.unseenCount, streakDays: connection.streakDays)
            }
            if result.sameMoment == true, let name = connections.first(where: { $0.id == connectionID })?.otherName {
                arrival = Arrival(id: eventID, connectionID: connectionID, senderName: name, kind: .sameMoment)
            }
            sendStates[connectionID] = .sent(eventID: eventID, signal: signal)
            if !defaults.bool(forKey: Self.reviewAskedKey) {
                defaults.set(true, forKey: Self.reviewAskedKey)
                reviewDue = !Self.isUITest
            }
            play(EffectTrigger(id: eventID, signal: signal), on: connectionID)
            if let updated = try? await api.listConnections() { connections = updated }
            // Pssting someone back takes their doodle off your widget (5A).
            if WidgetBridge.showsDoodle(from: connectionID) { await publishDoodle() }
            try? await Task.sleep(for: sentDisplayDuration)
            if sendStates[connectionID] == .sent(eventID: eventID, signal: signal) {
                sendStates[connectionID] = nil
            }
        } catch APIError.server(_, "not_connected") {
            let name = connections.first { $0.id == connectionID }?.otherName
            sendStates[connectionID] = nil
            connections.removeAll { $0.id == connectionID }
            notice = name.map { "\($0) isn't here any more." } ?? "That person isn't here any more."
        } catch APIError.server(_, "super_daily_limit") {
            noteReachable()
            sendStates[connectionID] = nil
            notice = "Today's Super Psst is used. Hold a person to see when it resets."
        } catch APIError.server(_, "invalid_doodle") {
            // The same strokes would fail again; never offer a retry that can't work.
            doodleStrokes[eventID] = nil
            sendStates[connectionID] = nil
        } catch APIError.server(429, _) {
            noteReachable()
            pausedUntil[connectionID] = now().addingTimeInterval(Self.pauseDuration)
            sendStates[connectionID] = .failed(eventID: eventID, signal: signal, reason: .rateLimited)
        } catch APIError.signedOut {
            doodleStrokes[eventID] = nil
            sendStates[connectionID] = nil
            resetLocalAccount()
        } catch {
            if case APIError.offline? = error as? APIError { noteUnreachable() }
            sendStates[connectionID] = .failed(eventID: eventID, signal: signal, reason: .retry)
        }
    }

    // MARK: Connections

    func remove(_ connection: ConnectionSummary) async throws {
        try await api.removeConnection(connection.id)
        connections.removeAll { $0.id == connection.id }
        sendStates[connection.id] = nil
        if WidgetBridge.showsDoodle(from: connection.id) { await publishDoodle() }
    }

    func block(_ connection: ConnectionSummary) async throws {
        try await api.blockUser(connection.otherId)
        connections.removeAll { $0.id == connection.id }
        sendStates[connection.id] = nil
        if WidgetBridge.showsDoodle(from: connection.id) { await publishDoodle() }
    }

    /// Reporting also blocks, on the server.
    func report(_ connection: ConnectionSummary) async throws {
        try await api.reportUser(connection.otherId)
        connections.removeAll { $0.id == connection.id }
        sendStates[connection.id] = nil
        if WidgetBridge.showsDoodle(from: connection.id) { await publishDoodle() }
    }

    func acceptInvite(code: String) async throws -> UUID? {
        let result = try await api.acceptInvite(code: code)
        if result.heldPsst == true, let id = result.connectionId { heldPsstConnections.insert(id) }
        await refresh()
        return result.connectionId
    }

    /// Joined through a Psst that was the invite (5A): its arrival says it was sent
    /// before they had Psst.
    @ObservationIgnored private var heldPsstConnections: Set<UUID> = []

    // MARK: Notifications

    @ObservationIgnored private var reportedNotificationStatus: Bool?

    /// Measurement (docs/METRICS.md): tells the server whether notifications
    /// are on, only when it changes. Nothing else about the device is sent.
    func reportNotificationStatus(enabled: Bool) async {
        guard enabled != reportedNotificationStatus, api.isSignedIn else { return }
        if (try? await api.setNotificationStatus(enabled)) != nil {
            reportedNotificationStatus = enabled
        }
    }

    func registerDeviceToken(_ token: String) async {
        if token != pendingDeviceToken {
            pendingDeviceToken = token
            tokenFailures = 0
            tokenRetryAt = .distantPast
        }
        await retryDeviceToken()
    }

    private func retryDeviceToken() async {
        guard !registeringToken, networkAvailable, api.isSignedIn,
              defaults.bool(forKey: Self.profileKey), now() >= tokenRetryAt,
              let token = pendingDeviceToken, token != lastRegisteredToken else { return }
        registeringToken = true
        let generation = accountGeneration
        do {
            try await api.registerDeviceToken(token, environment: AppConfig.pushEnvironment)
            guard generation == accountGeneration else { registeringToken = false; return }
            lastRegisteredToken = token
            tokenFailures = 0
            tokenRetryAt = .distantPast
        } catch {
            if generation == accountGeneration, pendingDeviceToken == token {
                tokenFailures += 1
                tokenRetryAt = now().addingTimeInterval(min(300, 15 * pow(2, Double(min(tokenFailures - 1, 5)))))
            }
        }
        registeringToken = false
        // A newer APNs token may have arrived while this request was suspended.
        if generation == accountGeneration, pendingDeviceToken != token { await retryDeviceToken() }
    }

    /// The person opened a notification: it was displayed, so it counts as seen.
    func openedNotification(_ payload: SignalPayload) async {
        try? await api.ackSignals([payload.eventID])
        let signal: Signal = payload.signal == .superPsst && defaults.object(forKey: "psst.superEffectsEnabled") as? Bool == false ? .psst : payload.signal
        play(EffectTrigger(id: payload.eventID, signal: signal), on: payload.connectionID)
        await refresh()
        if let sender = connections.first(where: { $0.id == payload.connectionID }) {
            var drawing: DoodleStrokes?
            if signal == .doodle, let latest = try? await api.latestDoodle(), latest.eventId == payload.eventID {
                drawing = latest.doodle
            }
            let opened = Arrival(id: payload.eventID, connectionID: sender.id, senderName: sender.otherName,
                                 kind: signal == .superPsst ? .superPsst : signal == .doodle ? .doodle : (payload.sameMoment ? .sameMoment : .signal),
                                 doodle: drawing)
            // Never cut off a moment that's on screen: the opened one plays next.
            if arrival == nil {
                arrival = opened
            } else if arrival?.id != opened.id {
                arrivalQueue.removeAll { $0.id == opened.id }
                arrivalQueue.insert(opened, at: 0)
            }
        }
    }

    /// A band tapped on the home-screen widget: send that person a Psst, the
    /// same as tapping their band at home (same pacing and retry rules).
    func psstFromWidget(_ connectionID: UUID) async {
        if !connections.contains(where: { $0.id == connectionID }) { await refresh() }
        if let connection = connections.first(where: { $0.id == connectionID }) {
            await tap(connection)?.value
        }
    }

    /// The current moment finished (or was tapped): show the next sender, if any.
    func nextArrival() {
        arrival = arrivalQueue.isEmpty ? nil : arrivalQueue.removeFirst()
    }

    /// Tapping the arrival sends a Psst back to that person. Tapping a same
    /// moment just closes it: you've both already pssted.
    func psstBack(_ arrival: Arrival) {
        nextArrival()
        guard arrival.kind != .sameMoment else { return }
        if let connection = connections.first(where: { $0.id == arrival.connectionID }) {
            tap(connection)
        }
    }

    /// "Psst back" from a notification. The reply's ID derives from the original,
    /// so a repeated action can't send twice. Returns false if it wasn't sent.
    func sendBack(_ payload: SignalPayload) async -> Bool {
        try? await api.ackSignals([payload.eventID])
        let reply = UUID.reply(to: payload.eventID)
        for attempt in 0..<2 {
            do {
                _ = try await api.sendSignal(eventID: reply, connectionID: payload.connectionID, signal: .psst)
                if WidgetBridge.showsDoodle(from: payload.connectionID) { await publishDoodle() }
                return true
            } catch APIError.offline where attempt == 0 {
                // One more try shortly: the reply ID is fixed, so it can't send twice.
                try? await Task.sleep(for: sendBackRetryDelay)
            } catch APIError.server(let status, _) where status >= 500 && attempt == 0 {
                try? await Task.sleep(for: sendBackRetryDelay)
            } catch {
                return false
            }
        }
        return false
    }

    // MARK: Account

    func deleteAccount() async throws {
        try await api.deleteAccount()
        resetLocalAccount()
    }

    private func resetLocalAccount() {
        api.signOutLocally()
        defaults.removeObject(forKey: Self.profileKey)
        defaults.removeObject(forKey: Self.welcomedKey)
        defaults.removeObject(forKey: Self.pinnedOrderKey)
        defaults.removeObject(forKey: Self.myNameKey)
        defaults.removeObject(forKey: Self.connectionsCacheKey)
        defaults.removeObject(forKey: Self.activityCacheKey)
        activity = []
        streakMoments = [:]
        reportedTimeZone = nil
        recapEnabled = nil
        showingRecap = false
        loadedRecapStatus = false
        myName = nil
        pinnedOrder = []
        recencyOrder = []
        isExistingUser = false
        defaults.removeObject(forKey: Self.coachKey)
        coachDismissed = false
        arrival = nil
        arrivalQueue = []
        pendingAcks = [:]
        displayed = []
        pausedUntil = [:]
        connections = []
        sendStates = [:]
        effects = [:]
        hasLoadedConnections = false
        lastRegisteredToken = nil
        pendingDeviceToken = nil
        tokenFailures = 0
        tokenRetryAt = .distantPast
        accountGeneration += 1
        connectionsLoadFailed = false
        phase = .needsName
        // No names left behind on the Home Screen or Lock Screen.
        WidgetBridge.publish([], unlocked: false, everyone: [])
        WidgetBridge.publishDoodle(nil)
    }
}
