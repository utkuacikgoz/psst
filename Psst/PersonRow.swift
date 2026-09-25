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
        configuration.label.background(color.opacity(configuration.isPressed ? Tokens.Band.pressedOpacity : 1))
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
