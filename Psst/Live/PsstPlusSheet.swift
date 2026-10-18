import AVFoundation
import StoreKit
import SwiftUI

/// Option PS1: the standard sheet. What Psst+ includes, one App Store price,
/// Unlock and Restore. Once unlocked, the same sheet holds the choices.
struct PsstPlusSheet: View {
    @Environment(Purchases.self) private var purchases
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var restoreMessage: String?
    @State private var restoring = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Tokens.Space.xs) {
                        Text("Psst+")
                            .font(.psst(.largeTitle, weight: .black))
                            .tracking(Tokens.Band.titleTracking)
                            .foregroundStyle(Color.psstCanvas)
                        Text(purchases.isUnlocked ? "Unlocked. Thank you!" : "One purchase. Yours for good.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: Tokens.Space.l, bottom: Tokens.Space.s, trailing: Tokens.Space.l))

                // 1A / 2A (owner picks, 18 Oct 2026): your word is the hero, before and
                // after buying. Colours and app icons are a quiet extra.
                Section {
                    WordHero(unlocked: purchases.isUnlocked)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.psstCanvas)
                }

                if purchases.isUnlocked {
                    SoundSection()
                    Section {
                        NavigationLink {
                            Form { IconSection() }.navigationTitle("App icon")
                        } label: {
                            LabeledContent("App icon", value: Personalization.icons.first {
                                $0.name == UIApplication.shared.alternateIconName
                            }?.title ?? "Purple")
                        }
                        Text("Band colours: hold someone's band → Colour…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Looks")
                    }
                } else {
                    Section {
                        perk("Unlimited Super Pssts", symbol: "sparkles", tint: 0xB87500)
                        perk("Your whisper sound", symbol: "speaker.wave.2.fill", tint: 0x187F69)
                        perk("Home Screen and Lock Screen widgets", symbol: "rectangle.grid.1x2.fill", tint: 0x5F61AE)
                    }
                    Section {
                        Text("Also: band colours and app icons")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    buySection
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
    }

    private func perk(_ title: String, symbol: String, tint: UInt32) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(hex: tint), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder private var buySection: some View {
        Section {
            if let price = purchases.displayPrice {
                Button {
                    Task { await purchases.buy(accountID: store.api.accountID) }
                } label: {
                    ZStack {
                        Text("Unlock for \(price)")
                            .opacity(purchases.state == .purchasing ? 0 : 1)
                        if purchases.state == .purchasing { ProgressView().tint(.white) }
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
                }
                .listRowBackground(Color.psstCanvas)
                .disabled(purchases.state == .purchasing)
            } else if purchases.loadFailed {
                Button("Couldn't reach the App Store. Try again") { Task { await purchases.load() } }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        // Unlock stands alone, so it reads as one whole button.
        Section {
            Button(restoring ? "Restoring…" : "Restore purchase") {
                restoring = true
                restoreMessage = nil
                Task {
                    // A failure already shows the App Store's reason below.
                    if await purchases.restore() {
                        restoreMessage = purchases.isUnlocked ? "Psst+ restored." : "No Psst+ purchase found for this Apple Account."
                    }
                    restoring = false
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(restoring)
        } footer: {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                switch purchases.state {
                case .pending:
                    Text("Waiting for approval. Psst+ unlocks by itself once it's approved.")
                case .failed(let message):
                    Text(message)
                default:
                    EmptyView()
                }
                if let restoreMessage { Text(restoreMessage) }
                Text("Pssting, replies and invites are always free. Super Pssts keep pacing limits, and recipients control their sounds and effects.")
                // Side by side when they fit; stacked at very large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tokens.Space.m) { legalLinks }
                    VStack(alignment: .leading, spacing: Tokens.Space.s) { legalLinks }
                }
            }
        }
    }

    @ViewBuilder private var legalLinks: some View {
        Link("Terms of use", destination: AppConfig.termsURL).font(.footnote)
        Link("Privacy policy", destination: AppConfig.privacyURL).font(.footnote)
    }
}

/// Alternate app icons (Psst+).
private struct IconSection: View {
    @State private var current = UIApplication.shared.alternateIconName
    @State private var isChanging = false
    @State private var changeError: String?

    var body: some View {
        Section {
            ForEach(Personalization.icons.indices, id: \.self) { index in
                let icon = Personalization.icons[index]
                Button {
                    guard !isChanging else { return }
                    isChanging = true
                    changeError = nil
                    UIApplication.shared.setAlternateIconName(icon.name) { error in
                        Task { @MainActor in
                            if error == nil { current = UIApplication.shared.alternateIconName }
                            else { changeError = "Couldn't change the icon. Try choosing it again." }
                            isChanging = false
                        }
                    }
                } label: {
                    HStack {
                        Group {
                            if icon.name == "AppIcon-Cat" { MischiefCat().padding(7) }
                            else { Text("psst").font(.psst(size: 13, weight: .heavy)) }
                        }
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color(hex: icon.preview), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityHidden(true)
                        Text(icon.title).foregroundStyle(.primary)
                        Spacer()
                        if current == icon.name { Image(systemName: "checkmark").foregroundStyle(Color.psstCanvas) }
                    }
                }
                .disabled(isChanging)
                .accessibilityAddTraits(current == icon.name ? .isSelected : [])
            }
        } header: {
            Text("App icon")
        } footer: {
            if let changeError { Text(changeError) }
        }
    }
}

/// Whisper sounds (Psst+): how Pssts sound on this phone. The server names the
/// file in each push; iPhone's silent switch and Focus still decide.
private struct SoundSection: View {
    static let choiceKey = "psst.plus.sound"
    static let sounds: [(title: String, file: String)] = [
        ("Whisper", "psst.wav"), ("Soft", "psst-soft.wav"), ("Quick", "psst-quick.wav"),
        ("Double", "psst-double.wav"), ("Low", "psst-low.wav"), ("Long", "psst-long.wav"),
    ]

    @Environment(LiveStore.self) private var store
    @AppStorage(Self.choiceKey) private var chosen = "psst.wav"
    @State private var player: AVAudioPlayer?
    @State private var failed = false

    var body: some View {
        Section {
            ForEach(Self.sounds.indices, id: \.self) { index in
                let sound = Self.sounds[index]
                HStack {
                    Button {
                        play(sound.file)
                    } label: {
                        Image(systemName: "play.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Play \(sound.title)")
                    Button {
                        choose(sound.file)
                    } label: {
                        HStack {
                            Text(sound.title).foregroundStyle(.primary)
                            Spacer()
                            if chosen == sound.file { Image(systemName: "checkmark").foregroundStyle(Color.psstCanvas) }
                        }
                    }
                    .accessibilityAddTraits(chosen == sound.file ? .isSelected : [])
                }
            }
        } header: {
            Text("Whisper sound")
        } footer: {
            Text(failed ? "That didn't save. Check you're online and try again."
                        : "How Pssts sound on this iPhone. Silent mode and Focus still apply.")
        }
    }

    private func play(_ file: String) {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func choose(_ file: String) {
        let previous = chosen
        chosen = file
        failed = false
        Task {
            do {
                try await store.api.setNotificationSound(file)
            } catch {
                chosen = previous
                failed = true
            }
        }
    }
}

/// Your word (owner picks 1A 2A 3A, 16 Oct 2026; English only since 17 Oct) as the
/// Psst+ hero (1A / 2A, 18 Oct): the word huge, a notification showing what your
/// people see, and the chips. Before buying the chips only preview; after, they save.
private struct WordHero: View {
    let unlocked: Bool

    @Environment(LiveStore.self) private var store
    @State private var chosen = "boop"
    @State private var failed = false
    @ScaledMetric(relativeTo: .largeTitle) private var wordSize: CGFloat = 56

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: Tokens.Space.s)]

    var body: some View {
        VStack(spacing: Tokens.Space.m) {
            Text(unlocked ? "YOUR WORD" : "SAY IT YOUR WAY")
                .font(.psst(.caption, weight: .bold))
                .tracking(Tokens.Band.labelTracking)
                .opacity(0.85)
            Text(verbatim: chosen)
                .font(.psst(size: wordSize, weight: .black))
                .tracking(Tokens.Band.titleTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityHidden(true)
            Text(unlocked ? "Your people see this when you psst them." : "Pick the word your people see when you psst them.")
                .font(.psst(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center)
            notification
            LazyVGrid(columns: columns, spacing: Tokens.Space.s) {
                ForEach(PsstWord.all, id: \.self) { word in
                    Button {
                        choose(word)
                    } label: {
                        Text(verbatim: word)
                            .font(.psst(.body, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(chosen == word ? Color.psstCanvas : Color.white)
                            .padding(.horizontal, Tokens.Space.s)
                            .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
                            .background(chosen == word ? Color.white : Color.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(word)
                    .accessibilityAddTraits(chosen == word ? .isSelected : [])
                }
            }
            if failed {
                Text("That didn't save. Check you're online and try again.")
                    .font(.psst(.footnote, weight: .semibold))
            }
        }
        .foregroundStyle(Color.white)
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity)
        .task {
            guard unlocked else { return }
            chosen = PsstWord.shown(try? await store.api.myPsstWord()) ?? "psst"
        }
    }

    /// What lands on their phone, with your name and the word.
    private var notification: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("PSST")
                Spacer()
                Text("now")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.5))
            Text(store.myName ?? "You").font(.subheadline.weight(.bold))
            Text(verbatim: chosen).font(.subheadline)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("What your people see: \(store.myName ?? "You"), \(chosen)")
    }

    private func choose(_ word: String) {
        guard unlocked else { chosen = word; return }
        let previous = chosen
        chosen = word
        failed = false
        Task {
            do {
                try await store.api.setPsstWord(word == "psst" ? nil : word)
            } catch {
                chosen = previous
                failed = true
            }
        }
    }
}

/// Option BC1: one person's colour, from eight. Only this phone changes.
struct ColourSheet: View {
    let connection: ConnectionSummary

    @Environment(Personalization.self) private var personalization
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.l), count: 4)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                LazyVGrid(columns: columns, spacing: Tokens.Space.l) {
                    ForEach(Personalization.palette, id: \.self) { hex in
                        let selected = personalization.colors[connection.id] == hex
                        Button {
                            personalization.setColor(hex, for: connection.id)
                            dismiss()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(Circle().stroke(Color.ink, lineWidth: selected ? 3 : 0).padding(-5))
                        }
                        .accessibilityLabel(Personalization.colourNames[hex] ?? "Colour")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Button("Use the usual colour") {
                    personalization.setColor(nil, for: connection.id)
                    dismiss()
                }
                .disabled(personalization.colors[connection.id] == nil)
                Text("Only your phone shows this.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Tokens.sheetInset)
            .navigationTitle("\(connection.otherName)'s colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
    }
}
