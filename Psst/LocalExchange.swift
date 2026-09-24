import Foundation
import Observation

/// The two sides of the on-device demonstration. Alex is fictional.
enum Party: String, Codable {
    case me
    case alex

    var other: Party { self == .me ? .alex : .me }
}

/// A signal as it will exist on the server: unique ID, sender, recipient, effect, timestamp.
/// In this prototype the timestamp comes from the device clock, not a server.
struct SignalEvent: Identifiable, Equatable {
    let id: UUID
    let from: Party
    let signal: Signal
    let createdAt: Date

    var to: Party { from.other }
}

enum SendOutcome: Equatable {
    /// Recorded and shown locally. Nothing left the device.
    case played(SignalEvent)
    /// The same event ID was already recorded; a retry never duplicates.
    case alreadyRecorded(SignalEvent)
    /// A repeat tap within the minimum interval; coalesced into the previous one.
    case tooSoon
    /// Several taps in a short window; sending resumes at `until`.
    case paused(until: Date)
}

/// What a person row can truthfully say in the simulation.
enum ExchangeStatus: Equatable {
    /// Nothing exchanged yet; tapping will use this signal.
    case ready(Signal)
    /// Played on this phone; the other side's screen has not been opened since.
    case playedLocally(Signal)
    /// The other side's simulated screen displayed it.
    case shownToOther(Signal)
    /// The other side sent this most recently.
    case received(Signal)
    case paused(until: Date)
}

/// Local, in-memory stand-in for the exchange between you and fictional Alex.
/// It models the rules the backend must later enforce (idempotency, pacing)
/// without claiming any remote delivery.
@Observable
final class LocalExchange {
    static let minimumInterval: TimeInterval = 0.8
    static let burstLimit = 5
    static let burstWindow: TimeInterval = 20
    /// Equal to the window, so the burst has aged out when the pause ends.
    static let pauseDuration: TimeInterval = burstWindow
    static let retainedEvents = 50
    static let favoriteKey = "psst.demo-alex.favoriteSignal"

    let partnerName = "Alex"

    /// Your chosen signal for Alex. Persisted on this device.
    private(set) var favorite: Signal
    private(set) var events: [SignalEvent] = []
    private(set) var seenEventIDs: Set<UUID> = []
    private(set) var pausedUntil: [Party: Date] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        favorite = defaults.string(forKey: Self.favoriteKey).flatMap(Signal.init(rawValue:)) ?? .psst
    }

    /// Changes the default signal. Never sends anything.
    func setFavorite(_ signal: Signal) {
        favorite = signal
        defaults.set(signal.rawValue, forKey: Self.favoriteKey)
    }

    /// The signal a plain tap sends from `party`. Alex mirrors what they last received.
    func tapSignal(for party: Party) -> Signal {
        switch party {
        case .me: favorite
        case .alex: latestEvent(to: .alex)?.signal ?? .psst
        }
    }

    @discardableResult
    func send(_ signal: Signal, from sender: Party, id: UUID = UUID()) -> SendOutcome {
        if let existing = events.first(where: { $0.id == id }) {
            return .alreadyRecorded(existing)
        }

        let time = now()
        if let until = pausedUntil[sender], until > time {
            return .paused(until: until)
        }

        let sent = events.filter { $0.from == sender }
        if let last = sent.last, time.timeIntervalSince(last.createdAt) < Self.minimumInterval {
            return .tooSoon
        }

        let recent = sent.filter { time.timeIntervalSince($0.createdAt) < Self.burstWindow }
        if recent.count >= Self.burstLimit {
            let until = time.addingTimeInterval(Self.pauseDuration)
            pausedUntil[sender] = until
            return .paused(until: until)
        }

        let event = SignalEvent(id: id, from: sender, signal: signal, createdAt: time)
        events.append(event)
        if events.count > Self.retainedEvents {
            events.removeFirst(events.count - Self.retainedEvents)
        }
        return .played(event)
    }

    func latestEvent(from party: Party) -> SignalEvent? {
        events.last { $0.from == party }
    }

    func latestEvent(to party: Party) -> SignalEvent? {
        events.last { $0.to == party }
    }

    func unseenEvents(to party: Party) -> [SignalEvent] {
        events.filter { $0.to == party && !seenEventIDs.contains($0.id) }
    }

    /// Records that `party`'s screen actually displayed everything addressed to them.
    func markSeen(by party: Party) {
        for event in events where event.to == party {
            seenEventIDs.insert(event.id)
        }
    }

    func activePause(for party: Party) -> Date? {
        guard let until = pausedUntil[party], until > now() else { return nil }
        return until
    }

    func clearExpiredPauses() {
        let time = now()
        pausedUntil = pausedUntil.filter { $0.value > time }
    }

    func status(for party: Party) -> ExchangeStatus {
        if let until = activePause(for: party) {
            return .paused(until: until)
        }
        // Events are appended in order, so position decides which came last.
        let outgoingIndex = events.lastIndex { $0.from == party }
        let incomingIndex = events.lastIndex { $0.to == party }

        if let incomingIndex, incomingIndex > (outgoingIndex ?? -1) {
            return .received(events[incomingIndex].signal)
        }
        if let outgoingIndex {
            let outgoing = events[outgoingIndex]
            return seenEventIDs.contains(outgoing.id)
                ? .shownToOther(outgoing.signal)
                : .playedLocally(outgoing.signal)
        }
        return .ready(tapSignal(for: party))
    }
}
