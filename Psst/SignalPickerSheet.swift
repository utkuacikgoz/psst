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
            VStack(spacing: 8) {
                SignalGlyph(signal: preview?.signal ?? selected, trigger: preview?.id,
                            baseSize: 54, tint: .white).frame(height: 80)
                Text(preview == nil ? "Choose below. Preview with ▶." : "Previewing \(preview!.signal.title) · not sent")
                    .font(.footnote).foregroundStyle(.white)
            }.padding(.vertical, 18).frame(maxWidth: .infinity).background(Color.psstCanvas)
            ForEach(Signal.allCases) { signal in
                SignalOptionRow(signal: signal, isSelected: selected == signal,
                                select: { onSelect(signal) }, preview: { play(signal) })
            }
            Text("Your next tap on \(personName) uses this signal.")
                .font(.footnote).foregroundStyle(Color.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
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
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 30
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Button(action: select) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(signal.title.uppercased()).bandTitle(signal.title, size: titleSize, tracking: -0.7)
                        Text(signal.meaning).font(.subheadline)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isSelected { Image(systemName: "checkmark").font(.title3.weight(.bold)) }
                }.multilineTextAlignment(.leading).padding(.vertical, 22)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(signal.title), \(signal.meaning)")
                .accessibilityHint("Selects this signal. Nothing is sent.")
                .accessibilityAddTraits(isSelected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
            Button(action: preview) {
                Image(systemName: "play.fill").font(.title3)
                    .frame(width: 48, height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Preview \(signal.title)")
        }.foregroundStyle(.white).padding(.horizontal, 24).background(signal.accent)
    }
}
