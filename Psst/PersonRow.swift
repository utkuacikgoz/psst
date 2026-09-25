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

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = Tokens.Band.titleSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingEffect = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Tokens.Space.m) {
                if showingEffect, let effect {
                    SignalGlyph(signal: effect.signal, trigger: effect.id, baseSize: 52, tint: .white)
                        .frame(minHeight: nameSize * 1.15)
                } else {
                    Text(name.uppercased())
                        .bandTitle(name, size: nameSize, tracking: Tokens.Band.titleTracking)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: nameSize * 1.15)
                }
                // Yo classic: the line appears only when something happened.
                if isBusy || !status.isEmpty {
                    HStack(spacing: Tokens.Space.s) {
                        if isBusy { ProgressView().tint(.white) }
                        else if let statusSymbol { Image(systemName: statusSymbol) }
                        Text(status).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, Tokens.Space.xl).padding(.vertical, Tokens.Band.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .overlay(alignment: .bottomTrailing) {
                if let cornerMark, !showingEffect {
                    HStack(spacing: Tokens.Space.xs) {
                        Text(cornerMark)
                        if cornerMark == "seen" { Image(systemName: "checkmark") }
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.m)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PersonBandStyle(color: color ?? .personBand(name), isDimmed: isDimmed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue([status, cornerMark.map { "Psst \($0)" } ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .task(id: effect?.id) {
            guard effect != nil else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { showingEffect = true }
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { showingEffect = false }
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
