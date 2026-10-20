import SwiftUI
import UserNotifications

/// Step 1 (NM1): the only identity Psst asks for. A plain question, then you
/// type straight into your own band, which is how you'll appear on their phone.
struct NameStepView: View {
    @Environment(LiveStore.self) private var store
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var questionSize: CGFloat = 34

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("psst")
                        .font(.psst(size: Tokens.Band.wordmarkSize, weight: .heavy))
                        .tracking(Tokens.Band.wordmarkTracking)
                        .padding(.horizontal, inset)
                        .padding(.vertical, Tokens.Space.l)

                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        Text("What do your people call you?")
                            .font(.psst(size: questionSize, weight: .heavy))
                            .tracking(Tokens.Band.titleTracking)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("It's how you'll show up on their phone.")
                            .font(.psst(.subheadline, weight: .medium))
                    }
                    .padding(.horizontal, inset)
                    .padding(.bottom, Tokens.Space.l)

                    NameBand(name: $name, focused: $focused, inset: inset, onSubmit: save)

                    Text("Only your people see it. Change it anytime in Settings.")
                        .font(.psst(.footnote, weight: .medium))
                        .padding(.horizontal, inset)
                        .padding(.top, Tokens.Space.m)

                    // 1A (owner pick, 18 Oct 2026): the App Store drops the invite link
                    // on install, so a newcomer can paste what they were sent. Apple's
                    // Paste button reads the clipboard only when tapped (no prompt).
                    if store.pendingInviteCode == nil {
                        HStack(spacing: Tokens.Space.m) {
                            Text("Someone sent you a Psst?")
                                .font(.psst(.subheadline, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            PasteButton(payloadType: String.self) { strings in
                                guard let code = strings.lazy.compactMap(InviteLink.code(inPasted:)).first else { return }
                                Task { @MainActor in store.pendingInviteCode = code }
                            }
                            .labelStyle(.titleOnly)
                            .buttonBorderShape(.capsule)
                            // A secure control: iOS refuses taps when its label and
                            // background lack contrast, so it stays dark with its own text.
                            .tint(Color.ink)
                        }
                        .padding(.horizontal, Tokens.Space.m)
                        .padding(.vertical, Tokens.Space.s)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, inset)
                        .padding(.top, Tokens.Space.l)
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.psst(.subheadline, weight: .semibold))
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
            VStack(spacing: 0) {
                termsLine
                    .padding(.horizontal, Tokens.Space.xl)
                    .padding(.vertical, Tokens.Space.m)
                PrimaryButton(title: "Continue", isBusy: isSaving, isEnabled: !trimmed.isEmpty, action: save)
            }
            .background(Color.psstCanvas)
        }
        .onAppear { focused = true }
    }

    /// 4A (owner pick, 20 Oct 2026): agreeing to the Terms before Psst starts
    /// (doodles are content people send each other; App Review guideline 1.2).
    private var termsLine: some View {
        var terms = AttributedString("Terms")
        terms.link = AppConfig.termsURL
        terms.underlineStyle = .single
        return (Text("By continuing you agree to the ") + Text(terms) + Text(". No bullying, no nasty doodles."))
            .font(.psst(.footnote, weight: .medium))
            .foregroundStyle(Color.onCanvasSecondary)
            .tint(Color.onCanvas)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do {
                try await store.createProfile(name: trimmed)
            } catch APIError.offline {
                error = "You're offline. Try again once you're back online."
            } catch {
                self.error = "That didn't save. Give it another go?"
            }
            isSaving = false
        }
    }
}

/// ED1: change your name from Settings with the same band you made it with.
struct NameEditSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var unchanged: Bool { trimmed == (store.myName ?? "") }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let inset = Tokens.sideInset(forWidth: proxy.size.width)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        NameBand(name: $name, focused: $focused, inset: inset, onSubmit: save)
                            .padding(.top, Tokens.Space.l)

                        Text("Your people see the new name the next time their Psst refreshes.")
                            .font(.psst(.footnote, weight: .medium))
                            .padding(.horizontal, inset)
                            .padding(.top, Tokens.Space.m)

                        if let error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.psst(.subheadline, weight: .semibold))
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
            .navigationTitle("Your name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.psstCanvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save).disabled(trimmed.isEmpty || unchanged)
                    }
                }
            }
        }
        .tint(.white)
        .environment(\.colorScheme, .dark)
        .onAppear {
            name = store.myName ?? ""
            focused = true
        }
    }

    private func save() {
        guard !trimmed.isEmpty, !isSaving else { return }
        guard !unchanged else { dismiss(); return }
        guard trimmed.count <= 40 else {
            error = "Names can be 1 to 40 characters."
            return
        }
        isSaving = true
        error = nil
        Task {
            do {
                try await store.rename(to: trimmed)
                dismiss()
            } catch APIError.offline {
                error = "You're offline. Try again once you're back online."
            } catch {
                self.error = "That didn't save. Try again."
            }
            isSaving = false
        }
    }
}

/// Your own band, typed into. The real text field is underneath, so typing,
/// VoiceOver and autofill work normally. On top, the band shows the name the
/// way contact bands do (uppercase). The name is saved as typed.
struct NameBand: View {
    @Binding var name: String
    var focused: FocusState<Bool>.Binding
    let inset: CGFloat
    let onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = Tokens.Band.titleSize

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let color = Color.personBand(trimmed.isEmpty ? "psst" : trimmed)
        ZStack {
            TextField("", text: $name)
                .font(.psst(size: titleSize, weight: .bold))
                .foregroundStyle(.clear)
                .tint(.clear)
                .multilineTextAlignment(.center)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused(focused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Your name")
                .accessibilityHint("Shown on the other person's phone when you psst them.")
                .onChange(of: name) { _, new in
                    if new.count > 40 { name = String(new.prefix(40)) }
                }

            HStack(spacing: 2) {
                Text(trimmed.isEmpty ? "NAME" : name.uppercased())
                    .bandTitle(trimmed.isEmpty ? "NAME" : name, size: titleSize, tracking: Tokens.Band.titleTracking)
                    .opacity(trimmed.isEmpty ? 0.55 : 1)
                    .multilineTextAlignment(.center)
                if focused.wrappedValue { BlinkingCaret(height: titleSize) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(minHeight: titleSize * 1.2)
        .padding(.horizontal, inset)
        .padding(.vertical, Tokens.Band.verticalPadding)
        .frame(maxWidth: .infinity)
        .background(color)
        .foregroundStyle(Color.onCanvas)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: color)
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
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
                    .font(.psst(size: Tokens.Band.wordmarkSize, weight: .heavy))
                    .tracking(Tokens.Band.wordmarkTracking)
                    .padding(.horizontal, inset)
                    .padding(.vertical, Tokens.Space.l)

                ScrollView {
                    // Same layout as the name step: left-aligned question, one line under it.
                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        Text("Hear it when someone pssts you")
                            .font(.psst(size: questionSize, weight: .heavy))
                            .tracking(Tokens.Band.titleTracking)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Pssts also wait for you in the app, whatever you choose.")
                            .font(.psst(.subheadline, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        NotificationPreview()
                            .padding(.top, Tokens.Space.xxl)
                    }
                    .padding(.horizontal, inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: 0) {
                    PrimaryButton(title: "Yes, notify me", isBusy: isAsking, isEnabled: true, action: allow)
                    Button {
                        // 6A (owner pick, 20 Oct 2026): Pssts still arrive, quietly, with no prompt.
                        Task { await NotificationPermission.quietly() }
                        store.finishNotificationChoice()
                    } label: {
                        Text("Not now")
                            .font(.psst(.body, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: Tokens.Band.barMinHeight)
                            .background(Color.bandShade)
                            .contentShape(Rectangle())
                    }
                    .disabled(isAsking)
                    .accessibilityHint("Pssts still wait for you in the app.")
                }
            }
            .foregroundStyle(Color.onCanvas)
        }
        .background(Color.psstCanvas.ignoresSafeArea())
    }

    private func allow() {
        guard !isAsking else { return }
        isAsking = true
        Task {
            _ = await NotificationPermission.ask()
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
            .font(.psst(.body, weight: .semibold))
            // Disabled reads as a quiet white band, not a muddy grey one.
            .foregroundStyle(isEnabled ? Color.ink : Color.psstCanvas)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Tokens.controlRadius)
                    .fill(isEnabled ? Color.surface : Color.surface.opacity(0.4))
            )
            .contentShape(RoundedRectangle(cornerRadius: Tokens.controlRadius))
        }
        .disabled(!isEnabled || isBusy)
        .accessibilityLabel(title)
    }
}

/// What a Psst looks like on the Lock Screen, so the question isn't abstract.
/// Illustration only: it's labelled as an example and is not a real notification.
private struct NotificationPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { card }
    }

    @ViewBuilder private var card: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Text("psst")
                .font(.psst(size: 13, weight: .heavy))
                .foregroundStyle(Color.onCanvas)
                .frame(width: 38, height: 38)
                .background(Color.psstCanvas, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Mia").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("now").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Psst").font(.subheadline)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(Tokens.Space.m)
        .background(Color.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example notification: Mia, Psst.")
        Text("Touch and hold it to psst back without opening Psst.")
            .font(.psst(.footnote, weight: .medium))
            .foregroundStyle(Color.onCanvasSecondary)
            .padding(.top, Tokens.Space.s)
    }
}

/// The one system permission Psst asks for: notifications (alerts and sound).
enum NotificationPermission {
    /// Shows iOS's prompt (only the first time it's asked) and registers for
    /// pushes if allowed.
    @MainActor static func ask() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    static let askedAgainKey = "psst.live.notificationAskedAgain"

    /// "Not now" (6A): no prompt; Pssts land quietly in Notification Center, where
    /// iOS offers Keep / Turn off.
    @MainActor static func quietly() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .provisional])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// True once ever: after the first Psst link you share, if iOS hasn't had a
    /// yes or no from you yet (quiet or never asked).
    @MainActor static func shouldAskAgain(defaults: UserDefaults = .standard) async -> Bool {
        guard !defaults.bool(forKey: askedAgainKey) else { return false }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .provisional || status == .notDetermined else { return false }
        defaults.set(true, forKey: askedAgainKey)
        return true
    }
}
