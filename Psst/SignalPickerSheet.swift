import SwiftUI

/// Deliberate signal choice with local previews. Nothing here sends.
struct SignalPickerSheet: View {
    let personName: String

    @Environment(LocalExchange.self) private var exchange
    @Environment(\.dismiss) private var dismiss
    @State private var preview: EffectTrigger?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    previewStage

                    Text("Tapping \(personName) uses the selected signal. Choosing or previewing here sends nothing.")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: Tokens.Space.m) {
                        ForEach(Signal.allCases) { signal in
                            SignalOptionRow(
                                signal: signal,
                                isSelected: exchange.favorite == signal,
                                select: { exchange.setFavorite(signal) },
                                preview: { play(signal) }
                            )
                        }
                    }

                    Text("All four signals are free to send and receive.")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(Tokens.sheetInset)
            }
            .background(Color.surface)
            .navigationTitle("Signal for \(personName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .sensoryFeedback(trigger: preview) { _, new in new?.signal.haptic }
    }

    private var previewStage: some View {
        let shown = preview?.signal ?? exchange.favorite

        return VStack(spacing: Tokens.Space.s) {
            SignalGlyph(signal: shown, trigger: preview?.id, baseSize: 48)
                .frame(height: 96)
            Text(preview == nil ? "Preview plays here only" : "Previewing \(shown.title) · not sent")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Space.l)
        .background(RoundedRectangle(cornerRadius: Tokens.controlRadius).fill(Color.surfaceInset))
        .accessibilityElement(children: .combine)
    }

    private func play(_ signal: Signal) {
        preview = EffectTrigger(signal: signal)
        AccessibilityNotification.Announcement("Previewing \(signal.title). Not sent.").post()
    }
}

private struct SignalOptionRow: View {
    let signal: Signal
    let isSelected: Bool
    let select: () -> Void
    let preview: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Space.s))
            : AnyLayout(HStackLayout(spacing: Tokens.Space.s))

        layout {
            Button(action: select) {
                HStack(spacing: Tokens.Space.m) {
                    Image(systemName: signal.symbolName)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(signal.accent)
                        .frame(width: Tokens.minTouch, height: Tokens.minTouch)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signal.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.ink)
                        Text(signal.meaning)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer(minLength: Tokens.Space.s)
                    if isSelected {
                        Label("Selected", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.psstCanvas)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: Tokens.minTouch, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(signal.title), \(signal.meaning)")
            .accessibilityHint("Makes \(signal.title) the signal for a tap. Nothing is sent.")
            .accessibilityAddTraits(isSelected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)

            Button(action: preview) {
                Label("Preview", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.psstCanvas)
                    .padding(.horizontal, Tokens.Space.m)
                    .frame(minHeight: Tokens.minTouch)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.controlRadius)
                            .stroke(Color.psstCanvas, lineWidth: 1.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Tokens.controlRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(signal.title)")
        }
        .padding(Tokens.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Tokens.controlRadius)
                .fill(Color.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.controlRadius)
                .stroke(isSelected ? Color.psstCanvas : .clear, lineWidth: 2)
        )
    }
}
