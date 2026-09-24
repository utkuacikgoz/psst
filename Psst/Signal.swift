import SwiftUI

/// The four free starter signals.
enum Signal: String, CaseIterable, Identifiable, Codable {
    case psst
    case squeeze
    case oi
    case duck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .psst: "Psst"
        case .squeeze: "Squeeze"
        case .oi: "Oi"
        case .duck: "Duck"
        }
    }

    var meaning: String {
        switch self {
        case .psst: "Thinking of you"
        case .squeeze: "A little affection"
        case .oi: "Hey, over here"
        case .duck: "For no reason at all"
        }
    }

    /// Stand-in artwork until the production effects are designed.
    var symbolName: String {
        switch self {
        case .psst: "ellipsis.message"
        case .squeeze: "heart"
        case .oi: "hand.wave"
        case .duck: "bird"
        }
    }

    /// Accent used on white surfaces. Each measures at least 5:1 against white.
    var accent: Color {
        switch self {
        case .psst: Color(hex: 0x2448D8)
        case .squeeze: Color(hex: 0xC8324B)
        case .oi: Color(hex: 0xB45309)
        case .duck: Color(hex: 0x0F766E)
        }
    }

    var motion: SignalMotion {
        switch self {
        case .psst: SignalMotion(pop: 1.15, squashX: 1, squashY: 1, tilt: 0, hop: -4)
        case .squeeze: SignalMotion(pop: 1.1, squashX: 1.3, squashY: 0.72, tilt: 0, hop: 0)
        case .oi: SignalMotion(pop: 1.2, squashX: 1, squashY: 1, tilt: 18, hop: 0)
        case .duck: SignalMotion(pop: 1.1, squashX: 0.9, squashY: 1.1, tilt: -12, hop: -16)
        }
    }

    /// Local haptic on devices that support it. Remote pushes cannot promise this.
    var haptic: SensoryFeedback {
        switch self {
        case .psst: .impact(flexibility: .soft, intensity: 0.6)
        case .squeeze: .impact(flexibility: .soft, intensity: 1)
        case .oi: .impact(weight: .heavy)
        case .duck: .impact(flexibility: .rigid, intensity: 0.8)
        }
    }
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
