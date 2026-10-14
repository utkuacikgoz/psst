import SwiftUI

/// A person is the action: one edge-to-edge band, with no nested controls.
struct PersonRow: View {
    let name: String
    let status: String
    let signal: Signal
    let effect: EffectTrigger?
    let accessibilityHint: String
    let action: () -> Void
    var isBusy = false
    var statusSymbol: String?
    var minHeight: CGFloat = Tokens.personRowMinHeight
    /// Option V2: a settled fact ("seen") sits quietly in the corner, not under the name.
    var cornerMark: String?
    /// Option T2: the band dims while sending is paused.
    var isDimmed = false
    /// Psst+ (BC1): a colour you chose for this person, on your phone only.
    var color: Color? = nil
    var exchangeDate: Date? = nil
    var exchangeFromMe: Bool? = nil
    /// 3A (owner pick, 14 Oct): a live streak of 3+ days shows as a flame and the
    /// number in the bottom-left corner, mirroring the Super Psst mark.
    var streakDays = 0
    /// Set for a few seconds when the streak just grew: "7 days in a row".
    var streakMoment: Int? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = Tokens.Band.titleSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Tokens.Space.m) {
                Text(name.uppercased())
                    .bandTitle(name, size: nameSize, tracking: Tokens.Band.titleTracking)
                    .fixedSize(horizontal: false, vertical: true)
                    // While sending (owner pick, 13 Oct): light sweeps across the name.
                    .modifier(SendingShimmer(active: isBusy))
                    // Sent (owner pick, 13 Oct, "Ps-st"): the name bumps twice with the pulses.
                    .keyframeAnimator(initialValue: 1.0, trigger: effect?.id) { content, scale in
                        content.scaleEffect(reduceMotion ? 1 : CGFloat(scale))
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.06, duration: 0.13)
                            CubicKeyframe(1.0, duration: 0.19)
                            CubicKeyframe(1.1, duration: 0.14)
                            CubicKeyframe(1.0, duration: 0.34)
                        }
                    }
                    .frame(minHeight: nameSize * 1.15)
                if let exchangeDate, let exchangeFromMe {
                    // One line (owner pick, 12 Oct): "Sent 1m ago · seen ✓". Until they
                    // open it, just "Sent 1m ago"; no second "sent" in the corner.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        HStack(spacing: Tokens.Space.xs) {
                            Text("\(exchangeFromMe ? "Sent" : "Received") \(Self.lowercasedStart(ExchangeTime.label(exchangeDate, now: context.date)))")
                            if exchangeFromMe && cornerMark == "seen" {
                                Text("· seen")
                                Image(systemName: "checkmark")
                            }
                        }
                        .font(.psst(.subheadline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // The moment a streak grows: one line for a few seconds (3A).
                if let streakMoment {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: "flame.fill")
                        Text("\(streakMoment) days in a row")
                    }
                    .font(.psst(.subheadline, weight: .bold))
                    .transition(.opacity)
                }
                // Failure or pause status stays separate from the timestamp. Sending shows
                // on the name itself (VoiceOver still hears it in the value).
                if !isBusy && !status.isEmpty {
                    HStack(spacing: Tokens.Space.s) {
                        if let statusSymbol { Image(systemName: statusSymbol) }
                        Text(status).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.psst(.subheadline, weight: .medium))
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, Tokens.Space.xl)
            .padding(.vertical, Tokens.Band.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            // A Super Psst nudges: the name shakes side to side (owner pick 1A, 14 Oct).
            .keyframeAnimator(initialValue: 0.0, trigger: effect?.signal == .superPsst ? effect?.id : nil) { content, x in
                content.offset(x: reduceMotion ? 0 : CGFloat(x))
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-10, duration: 0.05)
                    LinearKeyframe(10, duration: 0.08)
                    LinearKeyframe(-8, duration: 0.08)
                    LinearKeyframe(8, duration: 0.08)
                    LinearKeyframe(-4, duration: 0.07)
                    LinearKeyframe(0, duration: 0.07)
                }
            }
            .background { PsstRipple(trigger: effect?.id) }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if streakDays >= 3 {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: "flame.fill")
                        Text("\(streakDays)").monospacedDigit()
                    }
                    .font(.psst(.footnote, weight: .bold))
                    .foregroundStyle(Color.onBandSoft)
                    .keyframeAnimator(initialValue: 1.0, trigger: streakMoment) { content, scale in
                        content.scaleEffect(reduceMotion ? 1 : CGFloat(scale), anchor: .leading)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.35, duration: 0.15)
                            CubicKeyframe(1.0, duration: 0.35)
                        }
                    }
                    .frame(minHeight: Tokens.minTouch)
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.s)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Only when there's no exchange line to carry it.
                if let cornerMark, exchangeDate == nil {
                    HStack(spacing: Tokens.Space.xs) {
                        Text(cornerMark)
                        if cornerMark == "seen" { Image(systemName: "checkmark") }
                    }
                    .font(.psst(.footnote, weight: .bold))
                    .foregroundStyle(Color.onBandSoft)
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.m)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PersonBandStyle(color: color ?? .personBand(name), isDimmed: isDimmed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue([status, cornerMark.map { "Psst \($0)" } ?? "",
                             streakDays >= 3 ? "\(streakDays)-day streak" : "",
                             exchangeDate.map { "\(exchangeFromMe == true ? "Sent" : "Received") \($0.formatted(date: .complete, time: .shortened))" } ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}

extension PersonRow {
    /// "Just now" → "just now", "Yesterday" → "yesterday", so it reads after "Sent".
    /// Times ("14:05") and dates ("Oct 3") stay as they are.
    static func lowercasedStart(_ label: String) -> String {
        label == "Just now" || label == "Yesterday" ? label.lowercased() : label
    }
}

/// "Ps-st" (owner pick, 13 Oct 2026): two strong pulses on the band when a Psst
/// goes out or comes in, timed like the whisper and the vibration: a ring, then a
/// ring with a flash of light. Reduce Motion: one soft flash, no movement.
struct PsstRipple: View {
    let trigger: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pose {
        var ring1: CGFloat = 0, ring1Opacity: Double = 0
        var ring2: CGFloat = 0, ring2Opacity: Double = 0
        var flash: CGFloat = 0, flashOpacity: Double = 0
    }

    var body: some View {
        GeometryReader { geometry in
            let reach = max(geometry.size.width, geometry.size.height) * 1.6
            Group {
                if reduceMotion { softFlash(reach: reach) } else { pulses(reach: reach) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func shapes(_ pose: Pose, reach: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: reach * pose.flash, height: reach * pose.flash)
                .opacity(pose.flashOpacity)
            Circle()
                .stroke(Color.white, lineWidth: 6)
                .frame(width: reach * pose.ring1, height: reach * pose.ring1)
                .opacity(pose.ring1Opacity)
            Circle()
                .stroke(Color.white, lineWidth: 6)
                .frame(width: reach * pose.ring2, height: reach * pose.ring2)
                .opacity(pose.ring2Opacity)
        }
    }

    private func pulses(reach: CGFloat) -> some View {
        KeyframeAnimator(initialValue: Pose(), trigger: trigger) { pose in
            shapes(pose, reach: reach)
        } keyframes: { _ in
            // ps: a ring.
            KeyframeTrack(\.ring1) {
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.7, timingCurve: .easeOut)
            }
            KeyframeTrack(\.ring1Opacity) {
                MoveKeyframe(0.95)
                LinearKeyframe(0, duration: 0.7)
            }
            // st: a ring and a flash, a third of a second later.
            KeyframeTrack(\.ring2) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 0.32)
                LinearKeyframe(1, duration: 0.9, timingCurve: .easeOut)
            }
            KeyframeTrack(\.ring2Opacity) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 0.32)
                MoveKeyframe(0.95)
                LinearKeyframe(0, duration: 0.9)
            }
            KeyframeTrack(\.flash) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 0.32)
                LinearKeyframe(0.6, duration: 0.5, timingCurve: .easeOut)
            }
            KeyframeTrack(\.flashOpacity) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 0.32)
                MoveKeyframe(0.9)
                LinearKeyframe(0, duration: 0.5)
            }
        }
    }

    private func softFlash(reach: CGFloat) -> some View {
        KeyframeAnimator(initialValue: Pose(), trigger: trigger) { pose in
            shapes(pose, reach: reach)
        } keyframes: { _ in
            KeyframeTrack(\.flash) { MoveKeyframe(2) }
            KeyframeTrack(\.flashOpacity) {
                MoveKeyframe(0.35)
                LinearKeyframe(0, duration: 0.5)
            }
        }
    }
}

/// The name dims a little and a band of full brightness sweeps across it, left to
/// right, until the server accepts the Psst. Reduce Motion: a gentle fade instead.
struct SendingShimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    @ViewBuilder func body(content: Content) -> some View {
        if !active {
            // Ready to sweep again from the start next time.
            content.onAppear { phase = 0 }
        } else if reduceMotion {
            content
                .opacity(phase == 0 ? 1 : 0.55)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever()) { phase = 1 }
                }
        } else {
            content
                .opacity(0.5)
                .overlay {
                    content.mask {
                        GeometryReader { geometry in
                            LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: geometry.size.width * 0.6)
                                .offset(x: geometry.size.width * (phase * 1.6 - 0.6))
                        }
                    }
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1 }
                }
        }
    }
}

private struct PersonBandStyle: ButtonStyle {
    let color: Color
    var isDimmed = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(color.opacity(configuration.isPressed ? Tokens.Band.pressedOpacity : 1)
                .saturation(isDimmed ? 0.35 : 1)
                .brightness(isDimmed ? -0.12 : 0))
            .opacity(isDimmed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
