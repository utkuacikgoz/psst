import SwiftUI

private struct GlyphPose {
    var scaleX = 1.0
    var scaleY = 1.0
    var rotation = 0.0
    var offsetY = 0.0
    var opacity = 1.0
}

/// A signal's symbol that plays its short effect whenever `trigger` changes.
/// Every track ends at rest, so an interrupted or completed effect leaves the glyph unchanged.
/// With Reduce Motion the effect is a brief fade instead of movement.
struct SignalGlyph: View {
    let signal: Signal
    let trigger: UUID?
    var baseSize: CGFloat = 28
    var showsBurst = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var size: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? baseSize * 1.35 : baseSize
    }

    var body: some View {
        let motion = reduceMotion ? SignalMotion.still : signal.motion
        let fadeTo = reduceMotion ? 0.35 : 1.0

        ZStack {
            if showsBurst && !reduceMotion {
                BurstRing(color: signal.accent, trigger: trigger)
                    .frame(width: size * 1.6, height: size * 1.6)
            }

            KeyframeAnimator(initialValue: GlyphPose(), trigger: trigger) { pose in
                Image(systemName: signal.symbolName)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(signal.accent)
                    .scaleEffect(x: pose.scaleX, y: pose.scaleY)
                    .rotationEffect(.degrees(pose.rotation))
                    .offset(y: pose.offsetY)
                    .opacity(pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scaleX) {
                    CubicKeyframe(motion.squashX * motion.pop, duration: 0.14)
                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                }
                KeyframeTrack(\.scaleY) {
                    CubicKeyframe(motion.squashY * motion.pop, duration: 0.14)
                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                }
                KeyframeTrack(\.rotation) {
                    CubicKeyframe(motion.tilt, duration: 0.08)
                    CubicKeyframe(-motion.tilt, duration: 0.12)
                    CubicKeyframe(motion.tilt / 2, duration: 0.1)
                    CubicKeyframe(0, duration: 0.12)
                }
                KeyframeTrack(\.offsetY) {
                    CubicKeyframe(motion.hop, duration: 0.16)
                    SpringKeyframe(0, duration: 0.36, spring: .bouncy)
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(fadeTo, duration: 0.18)
                    CubicKeyframe(1, duration: 0.3)
                }
            }
        }
        .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
        .accessibilityHidden(true)
    }
}

/// A single ring that expands and fades once per trigger. Invisible at rest.
private struct BurstRing: View {
    let color: Color
    let trigger: UUID?

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: trigger) { progress in
            Circle()
                .stroke(color, lineWidth: 2)
                .scaleEffect(0.6 + progress * 0.6)
                .opacity(progress == 0 ? 0 : (1 - progress) * 0.6)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.01, duration: 0.01)
                CubicKeyframe(1, duration: 0.45)
                LinearKeyframe(0, duration: 0.01)
            }
        }
    }
}
