import SwiftUI
import UserNotifications

/// Step 1: the only identity Psst asks for. You type straight into your own
/// band, which is how you'll appear on the other person's phone.
struct NameStepView: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = Tokens.Band.titleSize

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("psst")
                        .font(.system(size: Tokens.Band.wordmarkSize, weight: .heavy))
                        .tracking(Tokens.Band.wordmarkTracking)
                        .padding(.horizontal, inset)
                        .padding(.vertical, Tokens.Space.l)

                    Text("YOUR NAME")
                        .font(.footnote.weight(.semibold))
                        .tracking(Tokens.Band.labelTracking)
                        .padding(.horizontal, inset)
                        .padding(.top, Tokens.Space.s)
                        .padding(.bottom, Tokens.Space.s)
                        .accessibilityHidden(true)

                    nameBand(inset: inset)

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, inset)
                            .padding(.top, Tokens.Space.l)
                    }
                }
                .foregroundStyle(Color.onCanvas)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.never)
        }
        .background(Color.psstCanvas.ignoresSafeArea())
        // Rides just above the keyboard.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: "Continue", isBusy: isSaving, isEnabled: !trimmed.isEmpty, action: save)
        }
        .onAppear { focused = true }
    }

    /// The real text field is underneath, so typing, VoiceOver and autofill work
    /// normally. On top, the band shows the name the way contact bands do
    /// (uppercase). The name is saved as typed.
    private func nameBand(inset: CGFloat) -> some View {
        let color = Color.personBand(trimmed.isEmpty ? "psst" : trimmed)
        return VStack(spacing: Tokens.Space.m) {
            ZStack {
                TextField("", text: $name)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .multilineTextAlignment(.center)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($focused)
                    .onSubmit(save)
                    .accessibilityLabel("Your name")
                    .accessibilityHint("Shown on the other person's phone when you send a signal.")
                    .onChange(of: name) { _, new in
                        if new.count > 40 { name = String(new.prefix(40)) }
                    }

                HStack(spacing: 2) {
                    Text(trimmed.isEmpty ? "NAME" : name.uppercased())
                        .bandTitle(trimmed.isEmpty ? "NAME" : name, size: titleSize, tracking: Tokens.Band.titleTracking)
                        .opacity(trimmed.isEmpty ? 0.55 : 1)
                        .multilineTextAlignment(.center)
                    if focused { BlinkingCaret(height: titleSize) }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(minHeight: titleSize * 1.2)

            Text("This band is you on their phone")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, inset)
        .padding(.vertical, Tokens.Band.verticalPadding)
        .frame(maxWidth: .infinity)
        .background(color)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: color)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func save() {
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do {
                try await store.createProfile(name: trimmed)
            } catch APIError.offline {
                error = "No internet right now. Try again once you're back online."
            } catch {
                self.error = "That didn't save. Give it another go?"
            }
            isSaving = false
        }
    }
}

/// A text cursor for the band, which draws its own lettering. Steady with Reduce Motion.
private struct BlinkingCaret: View {
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 3, height: height * 0.8)
            .opacity(visible ? 1 : 0)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    visible.toggle()
                }
            }
    }
}

/// Step 2 (option P6): one plain question before iOS asks for permission.
/// "Not now" is a real choice: signals still appear when Psst is opened.
struct NotificationStepView: View {
    @Environment(LiveStore.self) private var store
    @State private var isAsking = false
    @ScaledMetric(relativeTo: .largeTitle) private var questionSize: CGFloat = 40

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)
            VStack(alignment: .leading, spacing: 0) {
                Text("psst")
                    .font(.system(size: Tokens.Band.wordmarkSize, weight: .heavy))
                    .tracking(Tokens.Band.wordmarkTracking)
                    .padding(.horizontal, inset)
                    .padding(.vertical, Tokens.Space.l)

                ScrollView {
                    Text("Get a notification when someone taps you?")
                        .font(.system(size: questionSize, weight: .heavy))
                        .tracking(Tokens.Band.titleTracking)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, inset)
                        .frame(minHeight: proxy.size.height * 0.6)
                        .accessibilityAddTraits(.isHeader)
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: 0) {
                    PrimaryButton(title: "Yes, notify me", isBusy: isAsking, isEnabled: true, action: allow)
                    Button { store.finishNotificationChoice() } label: {
                        Text("Not now")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: Tokens.Band.barMinHeight)
                            .background(Color.bandShade)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("Signals still appear when you open Psst.")
                }
            }
            .foregroundStyle(Color.onCanvas)
        }
        .background(Color.psstCanvas.ignoresSafeArea())
    }

    private func allow() {
        isAsking = true
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            isAsking = false
            store.finishNotificationChoice()
        }
    }
}

/// Full-width white band button on the canvas.
struct PrimaryButton: View {
    let title: String
    var isBusy = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(Color.ink) }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Tokens.controlRadius)
                    .fill(isEnabled ? Color.surface : Color.surface.opacity(0.55))
            )
            .contentShape(RoundedRectangle(cornerRadius: Tokens.controlRadius))
        }
        .disabled(!isEnabled || isBusy)
        .accessibilityLabel(title)
    }
}
