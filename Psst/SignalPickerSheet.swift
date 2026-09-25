import SwiftUI

struct SignalPickerSheet: View {
    let personName: String
    @Environment(LocalExchange.self) private var exchange
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                SignalChoiceContent(personName: personName, selected: exchange.favorite,
                                    onSelect: { exchange.setFavorite($0) })
            }.psstSheetChrome(title: "Signal for \(personName)") { dismiss() }
        }.tint(Color.psstCanvas).environment(\.colorScheme, .light)
    }
}

struct SignalChoiceContent: View {
    let personName: String
    let selected: Signal
    let onSelect: (Signal) -> Void
    @State private var preview: EffectTrigger?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Space.s) {
                SignalGlyph(signal: preview?.signal ?? selected, trigger: preview?.id,
                            baseSize: Tokens.Band.pickerGlyphSize, tint: .white).frame(height: Tokens.Band.pickerStageHeight)
                Text(preview == nil ? "Choose below. Preview with ▶." : "Previewing \(preview!.signal.title) · not sent")
                    .font(.footnote).foregroundStyle(.white)
            }.padding(.vertical, Tokens.Space.l).frame(maxWidth: .infinity).background(Color.psstCanvas)
            ForEach(Signal.allCases) { signal in
                SignalOptionRow(signal: signal, isSelected: selected == signal,
                                select: { onSelect(signal) }, preview: { play(signal) })
            }
            Text("Your next tap on \(personName) uses this signal.")
                .font(.footnote).foregroundStyle(Color.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(Tokens.sheetInset)
        }.sensoryFeedback(trigger: preview) { _, new in new?.signal.haptic }
    }
    private func play(_ signal: Signal) {
        preview = EffectTrigger(signal: signal)
        AccessibilityNotification.Announcement("Previewing \(signal.title). Not sent.").post()
    }
}

extension View {
    func psstSheetChrome(title: String, doneTitle: String = "Done", onDone: @escaping () -> Void) -> some View {
        background(Color.surface)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(doneTitle, action: onDone) } }
    }
}

private struct SignalOptionRow: View {
    let signal: Signal
    let isSelected: Bool
    let select: () -> Void
    let preview: () -> Void
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = Tokens.Band.optionTitleSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: Tokens.Space.s))
        layout {
            Button(action: select) {
                HStack(spacing: Tokens.Space.m) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text(signal.title.uppercased()).bandTitle(signal.title, size: titleSize, tracking: Tokens.Band.optionTracking)
                        Text(signal.meaning).font(.subheadline)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isSelected { Image(systemName: "checkmark").font(.title3.weight(.bold)) }
                }.multilineTextAlignment(.leading).padding(.vertical, Tokens.Space.xl)
                    .frame(maxWidth: .infinity, minHeight: Tokens.Band.optionMinHeight, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(signal.title), \(signal.meaning)")
                .accessibilityHint("Selects this signal. Nothing is sent.")
                .accessibilityAddTraits(isSelected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
            Button(action: preview) {
                Image(systemName: "play.fill").font(.title3)
                    .frame(minWidth: Tokens.Band.headerControlHeight, minHeight: Tokens.Band.headerControlHeight).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Preview \(signal.title)")
        }.foregroundStyle(.white).padding(.horizontal, Tokens.Space.xl).background(signal.accent)
    }
}
