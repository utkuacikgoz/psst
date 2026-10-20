import Foundation
import Security
import WidgetKit

/// Hands the widget (PsstWidget) what it shows: the first people in home's
/// order, with their colours, when each last pssted you and the streak (the
/// free small widget, 7A), and whether Psst+ is unlocked. It's written to the
/// shared App Group and only when it changes.
@MainActor
enum WidgetBridge {
    struct Person: Codable, Equatable {
        let id: UUID
        let name: String
        let color: UInt32
        /// When they last pssted you (7A); nil if never, or not known yet.
        var lastPsstedYou: Date? = nil
        /// Days in a row you've both pssted (3A); the widget shows the flame from 3.
        var streakDays: Int? = nil

        /// The list only carries the latest Psst between you, so once you psst
        /// back it no longer says when they last pssted you: keep the time from before.
        func remembering(_ known: [UUID: Date]) -> Person {
            guard let earlier = known[id], lastPsstedYou.map({ $0 < earlier }) ?? true else { return self }
            var person = self
            person.lastPsstedYou = earlier
            return person
        }
    }

    static let peopleKey = "psst.widget.people"
    static let unlockedKey = "psst.widget.unlocked"
    /// Everyone, in home's order: the Control Center button's person picker (2A).
    static let everyoneKey = "psst.widget.everyone"

    static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PSSTAppGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$(") else { return nil }
        return UserDefaults(suiteName: group)
    }

    static func people(from connections: [ConnectionSummary], colorHex: (UUID, String) -> UInt32) -> [Person] {
        connections.prefix(3).map { person($0, colorHex: colorHex) }
    }

    private static func person(_ connection: ConnectionSummary, colorHex: (UUID, String) -> UInt32) -> Person {
        Person(id: connection.id, name: connection.otherName, color: colorHex(connection.id, connection.otherName),
               lastPsstedYou: connection.lastFromMe == false ? connection.lastCreatedAt : nil,
               streakDays: connection.streakDays)
    }

    /// Writes to the shared App Group, or to `store` in tests.
    static func publish(_ people: [Person], unlocked: Bool, everyone: [Person]? = nil, to store: UserDefaults? = nil) {
        guard let defaults = store ?? Self.defaults else { return }
        let known = lastPsstedYou(in: defaults)
        guard let data = try? JSONEncoder().encode(people.map { $0.remembering(known) }) else { return }
        let all = everyone.flatMap { try? JSONEncoder().encode($0.map { $0.remembering(known) }) }
        let allChanged = all != nil && all != defaults.data(forKey: everyoneKey)
        let newToken = WidgetLink.makeToken(in: defaults)
        guard data != defaults.data(forKey: peopleKey) || unlocked != defaults.bool(forKey: unlockedKey) || allChanged
            || newToken else { return }
        defaults.set(data, forKey: peopleKey)
        defaults.set(unlocked, forKey: unlockedKey)
        if let all { defaults.set(all, forKey: everyoneKey) }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    /// When each person last pssted you, from what was published before.
    private static func lastPsstedYou(in defaults: UserDefaults) -> [UUID: Date] {
        var known: [UUID: Date] = [:]
        for key in [peopleKey, everyoneKey] {
            let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Person].self, from: $0) } ?? []
            for person in stored {
                guard let date = person.lastPsstedYou else { continue }
                known[person.id] = max(known[person.id] ?? date, date)
            }
        }
        return known
    }

    /// The newest unanswered doodle for the widget (2A, 4A: shown with or without
    /// Psst+), or nil to take it off. The widget finds the sender's colour by id.
    static let doodleKey = "psst.widget.doodle"

    /// The doodle you hid from its ••• menu (1B): it stays off the widget even
    /// though it's still unanswered, until a newer one comes.
    static let hiddenDoodleKey = "psst.widget.doodle.hidden"

    static func hideDoodle(eventID: UUID, in store: UserDefaults? = nil) {
        guard let defaults = store ?? Self.defaults else { return }
        defaults.set(eventID.uuidString, forKey: hiddenDoodleKey)
        publishDoodle(nil, to: defaults)
    }

    static func publishDoodle(_ doodle: LatestDoodle?, to store: UserDefaults? = nil) {
        guard let defaults = store ?? Self.defaults else { return }
        let shown = doodle?.eventId.uuidString == defaults.string(forKey: hiddenDoodleKey) ? nil : doodle
        let data = shown.flatMap { try? JSONEncoder().encode($0) }
        guard data != defaults.data(forKey: doodleKey) else { return }
        defaults.set(data, forKey: doodleKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func showsDoodle(from connectionID: UUID, in store: UserDefaults? = nil) -> Bool {
        guard let data = (store ?? Self.defaults)?.data(forKey: doodleKey),
              let doodle = try? JSONDecoder().decode(LatestDoodle.self, from: data) else { return false }
        return doodle.connectionId == connectionID
    }

    static func everyone(from connections: [ConnectionSummary], colorHex: (UUID, String) -> UInt32) -> [Person] {
        connections.map { person($0, colorHex: colorHex) }
    }
}

/// Widget taps arrive as psst://psst/<connection id>?t=<token> and psst://plus.
/// A send needs this install's own token (8A, 18 Oct 2026), which only the app and
/// its widget can read, so a link on a web page can't send a Psst for you.
enum WidgetLink {
    case psst(UUID)
    case plus

    static let tokenKey = "psst.widget.linkToken"

    /// Creates this install's token once. True when it was just made.
    static func makeToken(in defaults: UserDefaults) -> Bool {
        guard defaults.string(forKey: tokenKey) == nil else { return false }
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return false }
        defaults.set(bytes.map { String(format: "%02x", $0) }.joined(), forKey: tokenKey)
        return true
    }

    static var sharedToken: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PSSTAppGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$(") else { return nil }
        return UserDefaults(suiteName: group)?.string(forKey: tokenKey)
    }

    init?(_ url: URL, token: String? = WidgetLink.sharedToken) {
        guard url.scheme?.lowercased() == "psst" else { return nil }
        switch url.host?.lowercased() {
        case "plus": self = .plus
        case "psst":
            guard let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)),
                  let token, !token.isEmpty,
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "t" })?.value == token else { return nil }
            self = .psst(id)
        default: return nil
        }
    }
}
