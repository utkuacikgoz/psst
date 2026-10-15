import SwiftUI

/// The signal a tap sends. The owner chose a single signal, Psst (25 Sep 2026).
/// It stays a type so the server's effect IDs and any future effect collections
/// have somewhere to live.
enum Signal: String, CaseIterable, Identifiable, Codable {
    case psst
    case superPsst = "super_psst"
    /// A doodle drawn for their widget (owner pick, 15 Oct 2026).
    case doodle

    var id: String { rawValue }
    var title: String {
        switch self {
        case .psst: "Psst"
        case .superPsst: "Super Psst"
        case .doodle: "Doodle"
        }
    }
    var meaning: String { "Thinking of you" }
    /// Stand-in artwork until the production effect is designed.
    var symbolName: String { "ellipsis.message" }
    /// White lettering stays readable on this band colour.
    var accent: Color { Color(hex: 0x2476AA) }
    /// One very light tick when you send. Arrivals play the "ps-st" pattern (PsstHaptics).
    var haptic: SensoryFeedback { .impact(weight: .light, intensity: 0.5) }
}

/// One playback of an effect. A new `id` replays it.
struct EffectTrigger: Equatable {
    var id = UUID()
    var signal: Signal
}
