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
    static let coachKey = "psst.live.coachShown"

    private(set) var phase: Phase = .loading
    private(set) var connections: [ConnectionSummary] = []
    private(set) var sendStates: [UUID: SendState] = [:]
    /// The effect currently playing on each row, keyed by connection. A new event ID replays it.
    private(set) var effects: [UUID: EffectTrigger] = [:]
    /// The most recent effect anywhere, for a single haptic per event.
    private(set) var latestEffect: EffectTrigger?
    /// A Psst that just arrived, shown full screen for a moment (R2).
    var arrival: Arrival?
    /// MA2: the senders still to show, oldest first, so the newest comes last.
    private(set) var arrivalQueue: [Arrival] = []
    private(set) var isOffline = false
    private(set) var hasLoadedConnections = false
    /// A short, factual message for the home screen (e.g. a connection that ended).
    var notice: String?
    /// Set from a psst://invite link; the home screen opens the invite sheet with it.
    var pendingInviteCode: String?
    /// IF2: someone new opened an invite link. Their start leads with the
    /// inviter; once they've chosen a name, the invite is accepted for them.
    private(set) var invitedBy: String?
    private(set) var introInviteCode: String?
    var introSeen = false
    /// True only while the home list is on screen in the foreground. Signals are
    /// acknowledged as seen only then, because only then were they displayed.
    var isHomeVisible = false

    let api: PsstAPI
    private let defaults: UserDefaults
    private let now: () -> Date
    private let sentDisplayDuration: Duration
    @ObservationIgnored private var lastTapAt: [UUID: Date] = [:]
    private var pausedUntil: [UUID: Date] = [:]
    /// People the user placed by dragging, top first. Kept on this device only.
    private(set) var pinnedOrder: [UUID] = []
    /// Everyone else, most recent first, as of the last time home appeared. Not
    /// re-sorted while you're tapping, so a band never moves under your finger.
    private var recencyOrder: [UUID] = []
    @ObservationIgnored private var lastRegisteredToken: String?

    static let profileKey = "psst.live.profileCreated"
    static let notificationChoiceKey = "psst.live.notificationChoiceMade"

    init(api: PsstAPI, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         sentDisplayDuration: Duration = .seconds(2)) {
        self.api = api
        self.defaults = defaults
        self.now = now
        self.sentDisplayDuration = sentDisplayDuration
        coachDismissed = defaults.bool(forKey: Self.coachKey)
        pinnedOrder = (defaults.stringArray(forKey: Self.pinnedOrderKey) ?? []).compactMap(UUID.init(uuidString:))
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
    }

    // MARK: Loading

    func refresh() async {
        do {
            connections = try await api.listConnections()
            if !hasLoadedConnections { reorderByRecency() }
            hasLoadedConnections = true
            isOffline = false
            await showUnseenIfVisible()
        } catch APIError.offline {
            isOffline = true
        } catch APIError.signedOut {
            resetLocalAccount()
        } catch {
            // Keep the last known list; the next refresh tries again.
        }
    }

    /// Plays each connection's newest unseen signal on its row, then reports them seen.
    /// Then welcomes anyone new.
    func showUnseenIfVisible() async {
        if isHomeVisible, let unseen = try? await api.listUnseen(), !unseen.isEmpty { await show(unseen) }
        welcomeNewConnections()
    }

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
                    kind: s.sameMoment == true ? .sameMoment : .signal,
                    position: many ? index + 1 : nil, total: many ? senders.count : nil)
        }
        if arrival == nil, let first = moments.first {
            arrival = first
            arrivalQueue = Array(moments.dropFirst())
        } else {
            arrivalQueue += moments
        }
        let shown = unseen.filter { signal in connections.contains { $0.id == signal.connectionId } }.map(\.id)
        if (try? await api.ackSignals(shown)) != nil, let updated = try? await api.listConnections() {
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

    func dismissCoach() {
        coachDismissed = true
        defaults.set(true, forKey: Self.coachKey)
    }

    // MARK: Order (O2, plus dragging)

    /// Pinned people first in the order placed, then new people, then everyone
    /// else most recent first.
    var orderedConnections: [ConnectionSummary] {
        let byID = Dictionary(connections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pinnedIDs = Set(pinnedOrder)
        let pinned = pinnedOrder.compactMap { byID[$0] }
        let known = recencyOrder.filter { byID[$0] != nil && !pinnedIDs.contains($0) }
        let knownIDs = Set(known)
        let new = Self.byRecency(connections.filter { !pinnedIDs.contains($0.id) && !knownIDs.contains($0.id) })
        return pinned + new + known.compactMap { byID[$0] }
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

    func send(connectionID: UUID, eventID: UUID, signal: Signal) async {
        sendStates[connectionID] = .sending(eventID: eventID, signal: signal)
        do {
            let result = try await api.sendSignal(eventID: eventID, connectionID: connectionID, signal: signal)
            isOffline = false
            if result.sameMoment == true, let name = connections.first(where: { $0.id == connectionID })?.otherName {
                arrival = Arrival(id: eventID, connectionID: connectionID, senderName: name, kind: .sameMoment)
            }
            sendStates[connectionID] = .sent(eventID: eventID, signal: signal)
            play(EffectTrigger(id: eventID, signal: signal), on: connectionID)
            if let updated = try? await api.listConnections() { connections = updated }
            try? await Task.sleep(for: sentDisplayDuration)
            if sendStates[connectionID] == .sent(eventID: eventID, signal: signal) {
                sendStates[connectionID] = nil
            }
        } catch APIError.server(_, "not_connected") {
            let name = connections.first { $0.id == connectionID }?.otherName
            sendStates[connectionID] = nil
            connections.removeAll { $0.id == connectionID }
            notice = name.map { "\($0) isn't here any more." } ?? "That person isn't here any more."
        } catch APIError.server(429, _) {
            isOffline = false
            pausedUntil[connectionID] = now().addingTimeInterval(Self.pauseDuration)
            sendStates[connectionID] = .failed(eventID: eventID, signal: signal, reason: .rateLimited)
        } catch APIError.signedOut {
            sendStates[connectionID] = nil
            resetLocalAccount()
        } catch {
            if case APIError.offline? = error as? APIError { isOffline = true }
            sendStates[connectionID] = .failed(eventID: eventID, signal: signal, reason: .retry)
        }
    }

    // MARK: Connections

    func remove(_ connection: ConnectionSummary) async throws {
        try await api.removeConnection(connection.id)
        connections.removeAll { $0.id == connection.id }
        sendStates[connection.id] = nil
    }

    func block(_ connection: ConnectionSummary) async throws {
        try await api.blockUser(connection.otherId)
        connections.removeAll { $0.id == connection.id }
        sendStates[connection.id] = nil
    }

    /// Reporting also blocks, on the server.
    func report(_ connection: ConnectionSummary) async throws {
        try await api.reportUser(connection.otherId)
        connections.removeAll { $0.id == connection.id }
        sendStates[connection.id] = nil
    }

    func acceptInvite(code: String) async throws -> UUID? {
        let result = try await api.acceptInvite(code: code)
        await refresh()
        return result.connectionId
    }

    // MARK: Notifications

    func registerDeviceToken(_ token: String) async {
        guard token != lastRegisteredToken, api.isSignedIn, defaults.bool(forKey: Self.profileKey) else { return }
        if (try? await api.registerDeviceToken(token, environment: AppConfig.pushEnvironment)) != nil {
            lastRegisteredToken = token
        }
    }

    /// The person opened a notification: it was displayed, so it counts as seen.
    func openedNotification(_ payload: SignalPayload) async {
        try? await api.ackSignals([payload.eventID])
        play(EffectTrigger(id: payload.eventID, signal: payload.signal), on: payload.connectionID)
        await refresh()
        if let sender = connections.first(where: { $0.id == payload.connectionID }) {
            arrival = Arrival(id: payload.eventID, connectionID: sender.id, senderName: sender.otherName,
                              kind: payload.sameMoment ? .sameMoment : .signal)
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
        do {
            _ = try await api.sendSignal(eventID: .reply(to: payload.eventID),
                                         connectionID: payload.connectionID, signal: payload.signal)
            return true
        } catch {
            return false
        }
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
        pinnedOrder = []
        recencyOrder = []
        arrival = nil
        arrivalQueue = []
        pausedUntil = [:]
        connections = []
        sendStates = [:]
        effects = [:]
        hasLoadedConnections = false
        lastRegisteredToken = nil
        phase = .needsName
    }
}
