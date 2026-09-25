import AVFoundation
import StoreKit
import SwiftUI

/// Option PS1: the standard sheet. What Psst+ includes, one App Store price,
/// Unlock and Restore. Once unlocked, the same sheet holds the choices.
struct PsstPlusSheet: View {
    @Environment(Purchases.self) private var purchases
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Tokens.Space.xs) {
                        Text("Psst+")
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(Color.psstCanvas)
                        Text(purchases.isUnlocked ? "Unlocked. Thank you!" : "One purchase. Yours for good.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    perk("Choose each person's colour", symbol: "paintpalette.fill", tint: 0xAC3E68)
                    perk("Alternate app icons", symbol: "app.fill", tint: 0x2476AA)
                    perk("Choose your whisper sound", symbol: "speaker.wave.2.fill", tint: 0x187F69)
                    perk("Home-screen widget (coming)", symbol: "rectangle.grid.1x2.fill", tint: 0xB87500)
                }

                if purchases.isUnlocked {
                    IconSection()
                    SoundSection()
                    Section {
                        Text("To change someone's colour, hold their band and choose Colour….")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
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
            if let product = purchases.product {
                Button {
                    Task { await purchases.buy() }
                } label: {
                    ZStack {
                        Text("Unlock for \(product.displayPrice)")
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
            Button("Restore purchase") { Task { await purchases.restore() } }
                .frame(maxWidth: .infinity)
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
                Text("Pssting, replies and invites are always free.")
                HStack(spacing: Tokens.Space.m) {
                    Link("Terms of use", destination: AppConfig.termsURL)
                    Link("Privacy policy", destination: AppConfig.privacyURL)
                }
            }
        }
    }
}

/// Alternate app icons (Psst+).
private struct IconSection: View {
    @State private var current = UIApplication.shared.alternateIconName

    var body: some View {
        Section("App icon") {
            ForEach(Personalization.icons.indices, id: \.self) { index in
                let icon = Personalization.icons[index]
                Button {
                    UIApplication.shared.setAlternateIconName(icon.name) { error in
                        if error == nil { current = icon.name }
                    }
                } label: {
                    HStack {
                        Text("psst")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color(hex: icon.preview), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityHidden(true)
                        Text(icon.title).foregroundStyle(.primary)
                        Spacer()
                        if current == icon.name { Image(systemName: "checkmark").foregroundStyle(Color.psstCanvas) }
                    }
                }
                .accessibilityAddTraits(current == icon.name ? .isSelected : [])
            }
        }
    }
}

/// Whisper sounds (Psst+): how Pssts sound on this phone. The server names the
/// file in each push; iPhone's silent switch and Focus still decide.
private struct SoundSection: View {
    static let choiceKey = "psst.plus.sound"
    static let sounds: [(title: String, file: String)] = [
        ("Whisper", "psst.wav"), ("Soft", "psst-soft.wav"), ("Quick", "psst-quick.wav"),
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
                        .accessibilityLabel("Colour \(Personalization.palette.firstIndex(of: hex)! + 1)")
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
        .presentationDetents([.medium])
    }
}
