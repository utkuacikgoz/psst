import SwiftUI

/// A large white row. The whole row is the send target; nothing else lives inside it.
struct PersonRow: View {
    let name: String
    let status: String
    let signal: Signal
    let effect: EffectTrigger?
    let accessibilityHint: String
    let action: () -> Void
    /// A small in-row progress treatment while a request is in flight.
    var isBusy = false
    /// Paired with the status text so meaning never relies on colour alone.
    var statusSymbol: String?

    @ScaledMetric(relativeTo: .title2) private var nameSize: CGFloat = 24
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Space.s))
                : AnyLayout(HStackLayout(spacing: Tokens.Space.m))

            layout {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(name)
                        .font(.system(size: nameSize, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Color.inkSecondary)
                        } else if let statusSymbol {
                            Image(systemName: statusSymbol)
                        }
                        Text(status)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SignalGlyph(signal: effect?.signal ?? signal, trigger: effect?.id)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Tokens.Space.xl)
            .padding(.vertical, Tokens.Space.l)
            .frame(maxWidth: .infinity, minHeight: Tokens.personRowMinHeight, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Tokens.controlRadius))
        }
        .buttonStyle(PersonRowStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(status)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}

private struct PersonRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Tokens.controlRadius)
                    .fill(configuration.isPressed ? Color.surfacePressed : Color.surface)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
