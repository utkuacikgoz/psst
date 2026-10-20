import SwiftUI
import UserNotifications

struct SettingsSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @AppStorage("psst.hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("psst.superEffectsEnabled") private var superEffectsEnabled = true
    @State private var savingSuper = false
    @State private var showingActivityPreview = false
    @State private var superSaveFailed = false
    @State private var editingName = false
    @State private var actions = SettingsActions()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var managing: ConnectionSummary?
    @State private var confirming: ConnectionAction?
    @State private var superPerson: ConnectionSummary?
    @State private var colouring: ConnectionSummary?
    @State private var showingPlus = false

    var body: some View {
        // Option S3: the standard grouped iPhone list.
        NavigationStack {
            // 1B (owner pick, 16 Oct 2026): a short front page like Apple's own Settings;
            // each row opens its own page.
            Form {
                // ED1: you, as your people see you.
                Section {
                    YouBand(name: store.myName) { editingName = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.personBand(store.myName ?? "psst"))
                }

                Section {
                    NavigationLink("Your Psst activity") { ActivityView() }
                    NavigationLink { recapPage } label: {
                        LabeledContent("Weekly recap", value: store.recapEnabled == false ? "Off" : "On")
                    }
                }

                Section {
                    NavigationLink { peoplePage } label: {
                        LabeledContent("People", value: "\(store.connections.count)")
                    }
                    NavigationLink("Notifications") { notificationsPage }
                    Button { showingPlus = true } label: {
                        HStack {
                            Text("Psst+").foregroundStyle(.primary)
                            Spacer()
                            if purchases.isUnlocked { Text("Unlocked").foregroundStyle(.secondary) }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                } footer: {
                    Text("People holds your people, open invites and blocked. Notifications holds haptics and Super Psst effects.")
                }

                Section {
                    NavigationLink("Privacy and help") { privacyPage }
                }

                Section {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        if isDeleting { ProgressView() } else { Text("Delete account") }
                    }
                    .disabled(isDeleting)
                } footer: {
                    VStack(spacing: Tokens.Space.l) {
                        if let deleteError { Text(deleteError) }
                        // The version, like Apple's own apps; long-press to copy it for support.
                        VStack(spacing: Tokens.Space.s) {
                            Text(Self.versionLine)
                                .textSelection(.enabled)
                            VersionCat()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Tokens.Space.xl)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $showingActivityPreview) { ActivityView() }
            .onAppear {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-PsstUITestLive"), let index = arguments.firstIndex(of: "-PsstDesignScreen"),
                   index + 1 < arguments.count, arguments[index + 1] == "activity" { showingActivityPreview = true }
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if let allowance = try? await store.api.superAllowance() { superEffectsEnabled = allowance.effectsEnabled }
        }
        .tint(Color.psstCanvas)
        .preferredColorScheme(.light)
        .task {
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            await actions.load(api: store.api)
        }
        .manageConnection(menuFor: $managing, confirming: $confirming, onDone: {
            Task { await actions.load(api: store.api) }
        }, onSuper: { superPerson = $0 },
           onColour: { if purchases.isUnlocked { colouring = $0 } else { showingPlus = true } })
        .sheet(item: $superPerson) { SuperPsstSheet(connection: $0) }
        .sheet(item: $colouring) { ColourSheet(connection: $0) }
        .sheet(isPresented: $showingPlus) { PsstPlusSheet() }
        .sheet(isPresented: $editingName) { NameEditSheet() }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your name, connections, and Psst history from Psst's server. It can't be undone.")
        }
    }

    // MARK: Pages one tap in (1B)

    private var recapPage: some View {
        Form {
            // Weekly recap: on from the start (owner pick 2A, 16 Oct 2026).
            Section {
                Toggle("Weekly recap", isOn: Binding(
                    get: { store.recapEnabled ?? true },
                    set: { on in Task { await store.setWeeklyRecap(on) } }))
                    .disabled(store.recapEnabled == nil)
            } footer: {
                Text("Sundays at 6 PM: your Pssts, your #1 and your longest streak. Only you see it.")
            }
        }
        .navigationTitle("Weekly recap")
    }

    private var peoplePage: some View {
        Form {
            Section {
                if store.connections.isEmpty {
                    Text("No one yet.").foregroundStyle(.secondary)
                }
                ForEach(store.orderedConnections) { connection in
                    Button {
                        managing = connection
                    } label: {
                        HStack {
                            Text(connection.otherName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityLabel("Manage \(connection.otherName)")
                }
                if !store.pinnedOrder.isEmpty {
                    Button("Sort everyone by most recent") { store.resetOrder() }
                }
            } header: {
                Text("People")
            } footer: {
                Text("Tap someone for Super Psst, colour, remove, block or report. Hold and drag a band on home to move it.")
            }

            // PI2: invites nobody has used yet, each cancellable.
            if !actions.openInvites.isEmpty || actions.invitesLoadFailed || !actions.listsLoaded {
                Section {
                    if actions.invitesLoadFailed {
                        Button("Couldn't load invites. Try again") { Task { await actions.load(api: store.api) } }
                            .disabled(actions.loadingLists)
                    } else if !actions.listsLoaded { ProgressView("Loading invites…") }
                    ForEach(actions.openInvites) { invite in
                        HStack {
                            if invite.kind == "psst" {
                                // 5A: a Psst waiting for someone new to open it.
                                Text("Psst waiting")
                            } else {
                                Text(invite.displayCode)
                                    .font(.body.monospaced())
                                    .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
                            }
                            Spacer()
                            Text(invite.expiresAt, format: .relative(presentation: .named))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Expires \(invite.expiresAt.formatted(.relative(presentation: .named)))")
                            Button("Cancel") { revoke(invite) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Cancel invite \(invite.displayCode)")
                                .disabled(actions.revoking.contains(invite.code))
                        }
                    }
                } header: {
                    Text("Open invites")
                } footer: {
                    Text(actions.inviteError ?? "Each works for up to 10 people. Cancel one to stop new joins.")
                }
            }

            Section {
                if actions.blockedLoadFailed {
                    Button("Couldn't load blocked people. Try again") { Task { await actions.load(api: store.api) } }
                        .disabled(actions.loadingLists)
                } else if !actions.listsLoaded { ProgressView("Loading blocked people…") }
                else if actions.blocked.isEmpty {
                    Text("No one.").foregroundStyle(.secondary)
                }
                ForEach(actions.blocked) { person in
                    HStack {
                        Text(person.displayName)
                        Spacer()
                        Button("Unblock") { unblock(person) }
                            .disabled(actions.unblocking.contains(person.userId))
                    }
                }
            } header: {
                Text("Blocked")
            } footer: {
                if let error = actions.unblockError { Text(error) }
            }
        }
        .navigationTitle("People")
    }

    private var notificationsPage: some View {
        Form {
            Section {
                if notificationStatus == .notDetermined {
                    // "Not now" at first launch: iOS has no switch for Psst
                    // until it has asked once, so ask here.
                    Button("Turn on notifications") {
                        Task {
                            _ = await NotificationPermission.ask()
                            notificationStatus = await UNUserNotificationCenter.current()
                                .notificationSettings().authorizationStatus
                        }
                    }
                } else {
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } footer: {
                Text(notificationText)
            }

            Section {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
                Toggle("Super Psst sounds and effects", isOn: Binding(
                    get: { superEffectsEnabled },
                    set: { enabled in
                        savingSuper = true; superSaveFailed = false
                        Task {
                            do { try await store.api.setSuperEffects(enabled); superEffectsEnabled = enabled }
                            catch { superSaveFailed = true }
                            savingSuper = false
                        }
                    }))
                    .disabled(savingSuper)
            } footer: {
                Text(superSaveFailed ? "Couldn't save. Try again when you're online." : "Turn off Super effects to receive them like ordinary Pssts. Silent mode and Focus still apply.")
            }
        }
        .navigationTitle("Notifications")
    }

    private var privacyPage: some View {
        Form {
            Section {
                Link("Privacy policy", destination: AppConfig.privacyURL)
                Link("Terms of use", destination: AppConfig.termsURL)
                Link("Help and support", destination: AppConfig.supportURL)
            } footer: {
                Text("Psst stores your name, connections, the last 30 days of Pssts and doodles, a running count of Pssts with each person, your settings and your notification token. Psst+ also keeps a purchase record for verification. It doesn't read your contacts or location.")
            }
        }
        .navigationTitle("Privacy and help")
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            "On. Sounds and alert style follow your iPhone's settings, including Focus and silent mode."
        case .denied:
            "Off. Pssts still wait for you in the app."
        default:
            "Off. You chose Not now when you started; turn them on to hear when someone pssts you."
        }
    }

    private func revoke(_ invite: OpenInvite) {
        Task { await actions.revoke(invite, api: store.api) }
    }

    private func unblock(_ person: BlockedPerson) {
        Task { await actions.unblock(person, api: store.api) }
    }

    private func deleteAccount() {
        isDeleting = true
        deleteError = nil
        Task {
            do {
                try await store.deleteAccount()
                dismiss()
            } catch {
                deleteError = "Your account is still here: that didn't go through. Check you're online and try again."
            }
            isDeleting = false
        }
    }
}

/// ED1: the top of Settings. Your band in your colour, and one way to change it.
extension SettingsSheet {
    /// "Psst 1.0.5": the App Store version only, no build number (owner, 14 Oct 2026).
    static var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "Psst \(version)"
    }
}

/// 1A (owner pick, 14 Oct 2026): a small sleeping cat under the version. Tap it
/// and it opens one eye for a moment.
private struct VersionCat: View {
    @State private var awake = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MoodCat(mood: awake ? .awake : .sleepy, eyes: LightPageCatColors(colorScheme).eyes,
                outline: LightPageCatColors(colorScheme).outline)
            .frame(width: 30, height: 27)
            .contentShape(Rectangle())
            .onTapGesture {
                awake = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    awake = false
                }
            }
    }
}

private struct YouBand: View {
    let name: String?
    let onEdit: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    var body: some View {
        VStack(spacing: Tokens.Space.s) {
            Text("YOU")
                .font(.psst(.caption, weight: .bold))
                .tracking(Tokens.Band.labelTracking * 2)
                .accessibilityHidden(true)
            if let name {
                Text(name.uppercased())
                    .bandTitle(name, size: titleSize, tracking: Tokens.Band.titleTracking)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Your name: \(name)")
            } else {
                Text("Add the name your people see.")
                    .font(.psst(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            Button(action: onEdit) {
                Text(name == nil ? "Add your name" : "Edit name")
                    .font(.psst(.subheadline, weight: .bold))
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.s)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
                    // Same capsule, a 44 pt tap area around it (11A).
                    .frame(minHeight: Tokens.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, Tokens.Space.xs)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Space.l)
        .padding(.horizontal, Tokens.Space.m)
    }
}
