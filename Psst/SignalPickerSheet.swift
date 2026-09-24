import SwiftUI

/// Local-preview picker for fictional Alex.
struct SignalPickerSheet: View {
    let personName: String

    @Environment(LocalExchange.self) private var exchange
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SignalChoiceContent(
                    personName: personName,
                    selected: exchange.favorite,
                    onSelect: { exchange.setFavorite($0) }
                )
                .padding(Tokens.sheetInset)
            }
            .psstSheetChrome(title: "Signal for \(personName)") { dismiss() }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
    }
}

/// Deliberate signal choice with local previews. Nothing here sends.
struct SignalChoiceContent: View {
    let personName: String
    let selected: Signal
    let onSelect: (Signal) -> Void

    @State private var preview: EffectTrigger?

    var body: some View {
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
                        isSelected: selected == signal,
                        select: { onSelect(signal) },
                        preview: { play(signal) }
                    )
                }
            }

            Text("All four signals are free to send and receive.")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
        }
        .sensoryFeedback(trigger: preview) { _, new in new?.signal.haptic }
    }

    private var previewStage: some View {
        let shown = preview?.signal ?? selected

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

extension View {
    /// White sheet surface with an inline title and a Done button.
    func psstSheetChrome(title: String, doneTitle: String = "Done", onDone: @escaping () -> Void) -> some View {
        background(Color.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(doneTitle, action: onDone)
                }
            }
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
