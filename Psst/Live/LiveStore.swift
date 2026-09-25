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

    private(set) var phase: Phase = .loading
    private(set) var connections: [ConnectionSummary] = []
    private(set) var sendStates: [UUID: SendState] = [:]
    /// The effect currently playing on each row, keyed by connection. A new event ID replays it.
    private(set) var effects: [UUID: EffectTrigger] = [:]
    /// The most recent effect anywhere, for a single haptic per event.
    private(set) var latestEffect: EffectTrigger?
    /// A Psst that just arrived, shown full screen for a moment (R2).
    var arrival: Arrival?
    private(set) var isOffline = false
    private(set) var hasLoadedConnections = false
    /// A short, factual message for the home screen (e.g. a connection that ended).
    var notice: String?
    /// Set from a psst://invite link; the home screen opens the invite sheet with it.
    var pendingInviteCode: String?
    /// True only while the home list is on screen in the foreground. Signals are
    /// acknowledged as seen only then, because only then were they displayed.
    var isHomeVisible = false

    let api: PsstAPI
    private let defaults: UserDefaults
    private let now: () -> Date
    private let sentDisplayDuration: Duration
    @ObservationIgnored private var lastTapAt: [UUID: Date] = [:]
    private var pausedUntil: [UUID: Date] = [:]
    @ObservationIgnored private var lastRegisteredToken: String?

    static let profileKey = "psst.live.profileCreated"
    static let notificationChoiceKey = "psst.live.notificationChoiceMade"

    init(api: PsstAPI, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         sentDisplayDuration: Duration = .seconds(2)) {
        self.api = api
        self.defaults = defaults
        self.now = now
        self.sentDisplayDuration = sentDisplayDuration
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
    }

    func finishNotificationChoice() {
        defaults.set(true, forKey: Self.notificationChoiceKey)
        phase = .ready
    }

    func rename(to name: String) async throws {
        try await api.setDisplayName(name)
    }

    // MARK: Loading

    func refresh() async {
        do {
            connections = try await api.listConnections()
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
        // One full-screen moment: the most recent sender.
        if let latest = newest.values.filter({ s in connections.contains { $0.id == s.connectionId } })
            .max(by: { $0.createdAt < $1.createdAt }) {
            arrival = Arrival(id: latest.id, connectionID: latest.connectionId, senderName: latest.senderName)
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
            _ = try await api.sendSignal(eventID: eventID, connectionID: connectionID, signal: signal)
            isOffline = false
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
            notice = name.map { "You're no longer connected with \($0)." } ?? "That connection has ended."
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
            arrival = Arrival(id: payload.eventID, connectionID: sender.id, senderName: sender.otherName)
        }
    }

    /// Tapping the arrival sends a Psst back to that person.
    func psstBack(_ arrival: Arrival) {
        self.arrival = nil
        if let connection = connections.first(where: { $0.id == arrival.connectionID }) {
            tap(connection)
        }
    }

    /// "Send back" from a notification. The reply's ID derives from the original,
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
        pausedUntil = [:]
        connections = []
        sendStates = [:]
        effects = [:]
        hasLoadedConnections = false
        lastRegisteredToken = nil
        phase = .needsName
    }
}
