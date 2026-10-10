import SwiftUI
import UserNotifications

struct SettingsSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("psst.hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("psst.superEffectsEnabled") private var superEffectsEnabled = true
    @State private var savingSuper = false
    @State private var showingActivityPreview = false
    @State private var superSaveFailed = false
    @State private var name = ""
    @State private var actions = SettingsActions()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var managing: ConnectionSummary?
    @State private var confirming: ConnectionAction?

    var body: some View {
        // Option S3: the standard grouped iPhone list.
        NavigationStack {
            Form {
                // ED1: you, as your people see you.
                Section {
                    HStack {
                        TextField("New name", text: $name)
                            .textContentType(.givenName)
                            .submitLabel(.done)
                            .onSubmit(rename)
                            .accessibilityLabel("New name")
                        Button("Save", action: rename)
                            .disabled(actions.isRenaming || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Your name")
                } footer: {
                    if let message = actions.nameMessage { Text(message) }
                }

                Section {
                    NavigationLink("Your Psst activity") { ActivityView() }
                } footer: {
                    Text("Your personal sent and received rankings over the last 30 days.")
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
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(notificationText)
                }

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
                    Text("Home puts whoever you pssted most recently first. Hold and drag a band to place someone yourself.")
                }

                // PI2: invites nobody has used yet, each cancellable.
                if !actions.openInvites.isEmpty {
                    Section {
                        ForEach(actions.openInvites) { invite in
                            HStack {
                                Text(invite.displayCode)
                                    .font(.body.monospaced())
                                    .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
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
                        Text(actions.inviteError ?? "Each works once. Cancel one you sent to the wrong person.")
                    }
                }

                Section {
                    if actions.blocked.isEmpty {
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

                Section {
                    Text("Psst stores your name, connections, the last 30 days of signals and daily allowances, and your notification token. Psst+ also keeps a purchase record for verification. It doesn't read your contacts or location.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Link("Privacy policy", destination: AppConfig.privacyURL)
                    Link("Terms of use", destination: AppConfig.termsURL)
                    Link("Help and support", destination: AppConfig.supportURL)
                } header: {
                    Text("Privacy and help")
                }

                Section {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        if isDeleting { ProgressView() } else { Text("Delete account") }
                    }
                    .disabled(isDeleting)
                } footer: {
                    if let deleteError { Text(deleteError) }
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
        .environment(\.colorScheme, .light)
        .task {
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            actions.blocked = (try? await store.api.listBlocked()) ?? []
            actions.openInvites = (try? await store.api.listOpenInvites()) ?? []
        }
        .manageConnection(menuFor: $managing, confirming: $confirming) {
            Task { actions.blocked = (try? await store.api.listBlocked()) ?? actions.blocked }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your name, connections, and signal history from Psst's server. It can't be undone.")
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            "On. Sounds and alert style follow your iPhone's settings, including Focus and silent mode."
        case .denied:
            "Off. Signals still appear when you open Psst."
        default:
            "Off. You chose Not now when you started; turn them on to hear when someone pssts you."
        }
    }

    private func rename() {
        let draft = name
        Task {
            if await actions.rename(to: draft, api: store.api, save: { try await store.rename(to: $0) }), name == draft { name = "" }
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
