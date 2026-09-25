import SwiftUI

/// The signal a tap sends. The owner chose a single signal, Psst (25 Sep 2026).
/// It stays a type so the server's effect IDs and any future effect collections
/// have somewhere to live.
enum Signal: String, CaseIterable, Identifiable, Codable {
    case psst

    var id: String { rawValue }
    var title: String { "Psst" }
    var meaning: String { "Thinking of you" }
    /// Stand-in artwork until the production effect is designed.
    var symbolName: String { "ellipsis.message" }
    /// White lettering stays readable on this band colour.
    var accent: Color { Color(hex: 0x2476AA) }
    var motion: SignalMotion { SignalMotion(pop: 1.15, squashX: 1, squashY: 1, tilt: 0, hop: -4) }
    /// Local haptic on devices that support it. Remote pushes cannot promise this.
    var haptic: SensoryFeedback { .impact(flexibility: .soft, intensity: 0.8) }
}

/// Parameters for the short, row-local effect. Identity values mean no movement.
struct SignalMotion {
    var pop: Double
    var squashX: Double
    var squashY: Double
    var tilt: Double
    var hop: Double

    static let still = SignalMotion(pop: 1, squashX: 1, squashY: 1, tilt: 0, hop: 0)
}

/// One playback of an effect. A new `id` replays it.
struct EffectTrigger: Equatable {
    var id = UUID()
    var signal: Signal
}
