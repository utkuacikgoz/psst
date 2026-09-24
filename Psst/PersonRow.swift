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

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingEffect = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                if showingEffect, let effect {
                    SignalGlyph(signal: effect.signal, trigger: effect.id, baseSize: 52, tint: .white)
                        .frame(minHeight: nameSize * 1.15)
                } else {
                    Text(name.uppercased())
                        .font(.system(size: nameSize, weight: .bold))
                        .tracking(-1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: nameSize * 1.15)
                }
                HStack(spacing: 7) {
                    if isBusy { ProgressView().tint(.white) }
                    else if let statusSymbol { Image(systemName: statusSymbol) }
                    Text(status).fixedSize(horizontal: false, vertical: true)
                }.font(.subheadline.weight(.medium))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.vertical, 30)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PersonBandStyle(color: .personBand(name)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(status)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(color.opacity(configuration.isPressed ? 0.72 : 1))
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
