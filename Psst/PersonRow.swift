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
                // Transient sending or failure status stays separate from the timestamp.
                if isBusy || !status.isEmpty {
                    HStack(spacing: Tokens.Space.s) {
                        if isBusy { ProgressView().tint(.white) }
                        else if let statusSymbol { Image(systemName: statusSymbol) }
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
            .overlay(alignment: .bottomTrailing) {
                // Only when there's no exchange line to carry it.
                if let cornerMark, !showingEffect, exchangeDate == nil {
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
                             exchangeDate.map { "\(exchangeFromMe == true ? "Sent" : "Received") \($0.formatted(date: .complete, time: .shortened))" } ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
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

extension PersonRow {
    /// "Just now" → "just now", "Yesterday" → "yesterday", so it reads after "Sent".
    /// Times ("14:05") and dates ("Oct 3") stay as they are.
    static func lowercasedStart(_ label: String) -> String {
        label == "Just now" || label == "Yesterday" ? label.lowercased() : label
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
