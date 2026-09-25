import Foundation
import WidgetKit

/// Hands the widget (PsstWidget) what it shows: the first people in home's
/// order, with their colours, and whether Psst+ is unlocked. It's written to the
/// shared App Group and only when it changes.
@MainActor
enum WidgetBridge {
    struct Person: Codable, Equatable {
        let id: UUID
        let name: String
        let color: UInt32
    }

    static let peopleKey = "psst.widget.people"
    static let unlockedKey = "psst.widget.unlocked"

    static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PSSTAppGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$(") else { return nil }
        return UserDefaults(suiteName: group)
    }

    static func people(from connections: [ConnectionSummary], colorHex: (UUID, String) -> UInt32) -> [Person] {
        connections.prefix(3).map { Person(id: $0.id, name: $0.otherName, color: colorHex($0.id, $0.otherName)) }
    }

    static func publish(_ people: [Person], unlocked: Bool, to defaults: UserDefaults? = defaults) {
        guard let defaults, let data = try? JSONEncoder().encode(people) else { return }
        guard data != defaults.data(forKey: peopleKey) || unlocked != defaults.bool(forKey: unlockedKey) else { return }
        defaults.set(data, forKey: peopleKey)
        defaults.set(unlocked, forKey: unlockedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Widget taps arrive as psst://psst/<connection id> and psst://plus.
enum WidgetLink {
    case psst(UUID)
    case plus

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "psst" else { return nil }
        switch url.host?.lowercased() {
        case "plus": self = .plus
        case "psst":
            guard let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return nil }
            self = .psst(id)
        default: return nil
        }
    }
}
