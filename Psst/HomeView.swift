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
            VStack(spacing: 0) {
                HStack {
                    Text("psst").font(.system(size: 40, weight: .heavy)).tracking(-2)
                    Spacer()
                    Text("LOCAL DEMO").font(.footnote.weight(.semibold)).tracking(1)
                }.foregroundStyle(.white).padding(.horizontal, 24).padding(.vertical, 22)
                ScrollView {
                    VStack(spacing: 0) {
                        PersonRow(name: exchange.partnerName, status: statusText,
                                  signal: exchange.favorite, effect: effect,
                                  accessibilityHint: "Plays \(exchange.favorite.title) locally. Nothing is sent.",
                                  action: tapAlex, minHeight: max(160, proxy.size.height * 0.38))
                            .accessibilityAction(named: "Choose signal") { showingPicker = true }
                        ChangeSignalButton(title: exchange.favorite.title,
                                           accessibilityLabel: "Signal for Alex: \(exchange.favorite.title)",
                                           accessibilityHint: "Choose or preview a signal. Nothing is sent.") { showingPicker = true }
                        Button { showingInvite = true } label: {
                            Image(systemName: "plus").font(.system(size: 40, weight: .light))
                                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 94)
                                .background(Color.addBand).contentShape(Rectangle())
                        }.accessibilityLabel("Invite someone")
                        if dynamicTypeSize.isAccessibilitySize { demoFooter }
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { demoFooter }
            }
        }
        .background(Color.psstCanvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(trigger: effect) { _, new in new?.signal.haptic }
        .task(id: exchange.activePause(for: .me)) {
            guard let until = exchange.activePause(for: .me) else { return }
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            exchange.clearExpiredPauses()
        }
        .sheet(isPresented: $showingPicker) { SignalPickerSheet(personName: exchange.partnerName) }
        .sheet(isPresented: $showingInvite) { InviteUnavailableSheet() }
        .fullScreenCover(isPresented: $showingAlexPhone, onDismiss: showReplyIfAny) { AlexPhoneView() }
    }
    private var demoFooter: some View {
        VStack(spacing: 3) {
            Button { showingAlexPhone = true } label: {
                HStack { Text("Alex’s side"); Spacer(); Image(systemName: "arrow.right") }
                    .font(.body.weight(.semibold)).frame(minHeight: 48)
            }.accessibilityLabel("View Alex's phone (simulated)")
            Text("Fictional Alex. Nothing leaves this phone.")
                .font(.footnote).foregroundStyle(Color.onCanvasSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(.white).padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 10)
    }
    private var statusText: String {
        switch exchange.status(for: .me) {
        case .ready(let signal): "Tap to \(signal.title.lowercased())"
        case .playedLocally(let signal): "\(signal.title) · played locally"
        case .shownToOther(let signal): "\(signal.title) · seen in demo"
        case .received(let signal): "\(signal.title) back from Alex"
        case .paused: "A little breather. Try again shortly."
        }
    }
    private func tapAlex() {
        switch exchange.send(exchange.favorite, from: .me) {
        case .played(let event): effect = EffectTrigger(id: event.id, signal: event.signal)
        case .paused: AccessibilityNotification.Announcement("Paused for a moment after several taps").post()
        case .tooSoon, .alreadyRecorded: break
        }
    }
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

struct LocalPreviewNotice: View {
    let text: String
    var color: Color = .onCanvasSecondary
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}
