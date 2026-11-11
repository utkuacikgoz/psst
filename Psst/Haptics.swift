import CoreHaptics
import SwiftUI

/// The "ps-st" vibration, timed to the whisper sound (scripts/make_psst_sound.py):
/// a light tick for the p, a short swell-and-fade buzz for the ss, a soft tick for the t.
/// Super Psst plays it stronger, twice. Local only: it plays when a Psst is shown in
/// the app; a remote push can't carry it.
@MainActor
enum PsstHaptics {
    private static var engine: CHHapticEngine?

    static func play(_ signal: Signal) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try readyEngine()
            try engine.makePlayer(with: pattern(for: signal)).start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil // rebuilt on the next Psst
        }
    }

    private static func readyEngine() throws -> CHHapticEngine {
        let ready = try engine ?? CHHapticEngine()
        ready.playsHapticsOnly = true
        ready.isAutoShutdownEnabled = true
        ready.resetHandler = { Task { @MainActor in PsstHaptics.engine = nil } }
        try ready.start()
        engine = ready
        return ready
    }

    static func pattern(for signal: Signal) throws -> CHHapticPattern {
        let strength: Float = signal == .superPsst ? 1 : 0.55
        let starts: [TimeInterval] = signal == .superPsst ? [0, 0.62] : [0]
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        for start in starts {
            events.append(tick(at: start, intensity: 0.8 * strength, sharpness: 0.5))
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8 * strength),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
            ], relativeTime: start + 0.09, duration: 0.34))
            // Swell in, hold, fade out; then back to full so the closing tick isn't muted.
            curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: start + 0.09, value: 0.25),
                .init(relativeTime: start + 0.17, value: 1),
                .init(relativeTime: start + 0.33, value: 1),
                .init(relativeTime: start + 0.43, value: 0.1),
                .init(relativeTime: start + 0.44, value: 1),
            ], relativeTime: 0))
            events.append(tick(at: start + 0.46, intensity: 0.6 * strength, sharpness: 0.7))
        }
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }

    private static func tick(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }
}

/// 7A (owner pick, 10 Nov 2026): small taps around sending, besides the light tick
/// once the server accepts (Signal.haptic). All follow Settings → Haptic feedback.
enum SendHaptics {
    /// The Settings switch they follow (on by default).
    static let settingKey = "psst.hapticsEnabled"
    /// A soft tick as a finger touches a band.
    static let touch: SensoryFeedback = .impact(flexibility: .soft, intensity: 0.45)
    /// A Psst that didn't make it.
    static let failed: SensoryFeedback = .error
    /// Tapping a band while sending to them is paused.
    static let paused: SensoryFeedback = .warning
}

extension LiveRowStatus {
    /// A Psst that didn't make it (the band reads "Didn't make it · tap to try again").
    var didNotSend: Bool {
        if case .notSent = self { return true }
        return false
    }
}
