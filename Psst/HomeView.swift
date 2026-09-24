import SwiftUI

struct HomeView: View {
    @Environment(LocalExchange.self) private var exchange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var effect: EffectTrigger?
    @State private var showingPicker = false
    @State private var showingInvite = false
    @State private var showingAlexPhone = false

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, inset)

                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        LocalPreviewNotice(text: "Local preview. Alex is fictional, and nothing leaves this phone.")
                            .padding(.bottom, Tokens.Space.s)

                        PersonRow(
                            name: exchange.partnerName,
                            status: statusText,
                            signal: exchange.favorite,
                            effect: effect,
                            accessibilityHint: "Plays \(exchange.favorite.title) here. Nothing is sent.",
                            action: tapAlex
                        )
                        .accessibilityAction(named: "Choose signal") { showingPicker = true }

                        signalButton

                        if dynamicTypeSize.isAccessibilitySize {
                            alexPhoneButton.padding(.top, Tokens.Space.l)
                        }
                    }
                    .padding(.horizontal, inset)
                    .padding(.top, Tokens.Space.l)
                    .padding(.bottom, Tokens.Space.xl)
                }
                .pinnedFooter(!dynamicTypeSize.isAccessibilitySize, inset: inset) { alexPhoneButton }
            }
        }
        .background(Color.psstCanvas.ignoresSafeArea())
        .sensoryFeedback(trigger: effect) { _, new in new?.signal.haptic }
        .task(id: exchange.activePause(for: .me)) {
            guard let until = exchange.activePause(for: .me) else { return }
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            exchange.clearExpiredPauses()
        }
        .sheet(isPresented: $showingPicker) {
            SignalPickerSheet(personName: exchange.partnerName)
        }
        .sheet(isPresented: $showingInvite) {
            InviteUnavailableSheet()
        }
        .fullScreenCover(isPresented: $showingAlexPhone, onDismiss: showReplyIfAny) {
            AlexPhoneView()
        }
    }

    private var header: some View {
        HStack {
            Text("psst")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Color.onCanvas)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingInvite = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Color.onCanvas)
                    .frame(width: Tokens.minTouch, height: Tokens.minTouch)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Invite someone")
        }
        .padding(.top, Tokens.Space.s)
    }

    private var signalButton: some View {
        ChangeSignalButton(
            title: "Signal for Alex: \(exchange.favorite.title)",
            accessibilityLabel: "Signal for Alex: \(exchange.favorite.title)",
            accessibilityHint: "Opens signal choices and previews. Nothing is sent."
        ) { showingPicker = true }
    }

    private var alexPhoneButton: some View {
        Button {
            showingAlexPhone = true
        } label: {
            Label("View Alex's phone (simulated)", systemImage: "iphone")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onCanvas)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Space.m)
                .padding(.vertical, Tokens.Space.s)
                .frame(maxWidth: .infinity, minHeight: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.controlRadius)
                        .stroke(Color.onCanvasSecondary, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: Tokens.controlRadius))
        }
    }

    private var statusText: String {
        switch exchange.status(for: .me) {
        case .ready(let signal):
            "Tap to play \(signal.title)"
        case .playedLocally(let signal):
            "\(signal.title) · played on this phone only"
        case .shownToOther(let signal):
            "\(signal.title) · shown on Alex's simulated phone"
        case .received(let signal):
            "Alex sent \(signal.title) back"
        case .paused:
            "Paused for a moment after several taps"
        }
    }

    private func tapAlex() {
        let outcome = exchange.send(exchange.favorite, from: .me)
        switch outcome {
        case .played(let event):
            effect = EffectTrigger(id: event.id, signal: event.signal)
        case .paused:
            AccessibilityNotification.Announcement("Paused for a moment after several taps").post()
        case .tooSoon, .alreadyRecorded:
            break
        }
    }

    /// Identifies Alex first (the row), then plays what Alex sent.
    private func showReplyIfAny() {
        guard let reply = exchange.unseenEvents(to: .me).last else { return }
        exchange.markSeen(by: .me)
        AccessibilityNotification.Announcement("Alex sent \(reply.signal.title) back").post()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 300))
            effect = EffectTrigger(id: reply.id, signal: reply.signal)
        }
    }
}

/// Small, always-visible label that the exchange is simulated.
struct LocalPreviewNotice: View {
    let text: String
    var color: Color = .onCanvasSecondary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "iphone")
        }
        .font(.footnote)
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    HomeView()
        .environment(LocalExchange())
}
