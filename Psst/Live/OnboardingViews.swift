import SwiftUI
import UserNotifications

/// Step 1: the only identity Psst asks for.
struct NameStepView: View {
    @Environment(LiveStore.self) private var store
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        OnboardingLayout(
            title: "What should people see?",
            message: "Your name appears on the other person's phone when you send a signal. It's the only thing Psst asks for.",
            error: error
        ) {
            TextField("", text: $name, prompt: Text("Your name").foregroundStyle(Color.inkSecondary))
                .font(.title3)
                .foregroundStyle(Color.ink)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .focused($focused)
                .onSubmit(save)
                .padding(.horizontal, Tokens.Space.l)
                .frame(minHeight: Tokens.Band.barMinHeight)
                .background(RoundedRectangle(cornerRadius: Tokens.controlRadius).fill(Color.surface))
                .accessibilityLabel("Your name")
                .onChange(of: name) { _, new in
                    if new.count > 40 { name = String(new.prefix(40)) }
                }
        } actions: {
            PrimaryButton(title: "Continue", isBusy: isSaving, isEnabled: !trimmed.isEmpty, action: save)
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do {
                try await store.createProfile(name: trimmed)
            } catch APIError.offline {
                error = "You're offline. Connect to the internet and try again."
            } catch {
                self.error = "Couldn't save your name. Try again."
            }
            isSaving = false
        }
    }
}

/// Step 2: explain before asking, and make "Not now" a real choice.
struct NotificationStepView: View {
    @Environment(LiveStore.self) private var store
    @State private var isAsking = false

    var body: some View {
        OnboardingLayout(
            title: "Know when someone taps you",
            message: "Psst shows a notification with the person's name and signal. You can turn off sounds or alerts anytime in Settings. Without notifications, signals still appear here when you open Psst.",
            error: nil
        ) {
            EmptyView()
        } actions: {
            PrimaryButton(title: "Turn on notifications", isBusy: isAsking, isEnabled: true) {
                isAsking = true
                Task {
                    let granted = (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])) ?? false
                    if granted { UIApplication.shared.registerForRemoteNotifications() }
                    isAsking = false
                    store.finishNotificationChoice()
                }
            }
            Button("Not now") { store.finishNotificationChoice() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onCanvas)
                .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
        }
    }
}

struct OnboardingLayout<Field: View, Actions: View>: View {
    let title: String
    let message: String
    let error: String?
    @ViewBuilder let field: Field
    @ViewBuilder let actions: Actions

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.l) {
                        Text("psst")
                            .font(.system(size: Tokens.Band.wordmarkSize, weight: .heavy))
                            .tracking(Tokens.Band.wordmarkTracking)
                            .foregroundStyle(Color.onCanvas)
                            .padding(.bottom, Tokens.Space.xl)
                        Text(title)
                            .font(.system(.title, weight: .semibold))
                            .foregroundStyle(Color.onCanvas)
                            .accessibilityAddTraits(.isHeader)
                        Text(message)
                            .font(.body)
                            .foregroundStyle(Color.onCanvasSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        field
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.onCanvas)
                        }
                    }
                    .padding(.horizontal, inset)
                    .padding(.top, Tokens.Space.l)
                }
                .scrollDismissesKeyboard(.interactively)
                VStack(spacing: Tokens.Space.s) { actions }
                    .padding(.horizontal, inset)
                    .padding(.bottom, Tokens.Space.l)
            }
        }
        .background(Color.psstCanvas.ignoresSafeArea())
    }
}

/// White filled button on the cobalt canvas.
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
