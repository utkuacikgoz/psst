import CoreText
import SwiftUI
import WidgetKit

/// The widgets (Psst+). Home screen: your first people as colour bands. Lock
/// Screen: your first person. Tapping a person opens Psst and sends them a Psst,
/// just like tapping their band at home. The app writes the list to the shared
/// App Group (see WidgetBridge).
@main
struct PsstWidgetBundle: WidgetBundle {
    init() {
        // Uses the app's own copy of the font (5A, 14 Oct 2026): the widget sits
        // inside Psst.app/PlugIns, so the app bundle is two folders up.
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        for path in ["InterTight-Black.ttf", "Fonts/InterTight-Black.ttf"] {
            let url = app.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                break
            }
        }
    }

    var body: some Widget {
        PeopleWidget()
        FavouriteWidget()
    }
}

/// Lock Screen: one tap on your first person (the top of home).
struct FavouriteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PsstFavourite", provider: Provider()) { entry in
            FavouriteView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Your person")
        .description("One tap sends a Psst to the first person on your home screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct FavouriteView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.unlocked {
            label(big: "psst", small: "Psst+ puts your person here")
                .widgetURL(URL(string: "psst://plus"))
        } else if let person = entry.people.first {
            label(big: family == .accessoryCircular ? initials(person.name) : person.name.uppercased(),
                  small: "Tap to psst")
                .widgetURL(URL(string: "psst://psst/\(person.id.uuidString)"))
                .accessibilityLabel("Send \(person.name) a Psst")
        } else {
            label(big: "psst", small: "Invite someone to psst")
                .widgetURL(URL(string: "psst://home"))
        }
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    @ViewBuilder private func label(big: String, small: String) -> some View {
        if family == .accessoryCircular {
            Text(big)
                .font(.custom("InterTight-Black", size: big.count > 2 ? 15 : 24))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(big)
                    .font(.custom("InterTight-Black", size: 22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(small)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PeopleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetPerson.kind, provider: Provider()) { entry in
            PeopleView(entry: entry)
                .containerBackground(Color(hex: 0x713F93), for: .widget)
        }
        .configurationDisplayName("Your people")
        .description("Tap someone to send them a Psst.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// Mirrors WidgetBridge.Person in the app.
struct WidgetPerson: Codable, Hashable {
    static let kind = "PsstPeople"
    let id: UUID
    let name: String
    let color: UInt32
}

struct Entry: TimelineEntry {
    let date = Date()
    let people: [WidgetPerson]
    let unlocked: Bool
}

struct Provider: TimelineProvider {
    private var defaults: UserDefaults? {
        (Bundle.main.object(forInfoDictionaryKey: "PSSTAppGroup") as? String).flatMap(UserDefaults.init(suiteName:))
    }

    private func read() -> Entry {
        let people = defaults?.data(forKey: "psst.widget.people")
            .flatMap { try? JSONDecoder().decode([WidgetPerson].self, from: $0) } ?? []
        return Entry(people: people, unlocked: defaults?.bool(forKey: "psst.widget.unlocked") ?? false)
    }

    func placeholder(in context: Context) -> Entry {
        Entry(people: [WidgetPerson(id: UUID(), name: "Mia", color: 0x5F61AE)], unlocked: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the widget whenever the people change.
        completion(Timeline(entries: [read()], policy: .never))
    }
}

struct PeopleView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var shown: [WidgetPerson] {
        Array(entry.people.prefix(family == .systemSmall ? 1 : 3))
    }

    var body: some View {
        if !entry.unlocked {
            message("Psst+ puts your people here", url: "psst://plus")
        } else if shown.isEmpty {
            message("Invite someone to psst", url: "psst://home")
        } else if family == .systemSmall, let person = shown.first {
            band(person).widgetURL(url(for: person))
        } else {
            VStack(spacing: 0) {
                ForEach(shown, id: \.self) { person in
                    Link(destination: url(for: person)) { band(person) }
                }
            }
        }
    }

    private func url(for person: WidgetPerson) -> URL {
        URL(string: "psst://psst/\(person.id.uuidString)")!
    }

    private func band(_ person: WidgetPerson) -> some View {
        Text(person.name.uppercased())
            .font(.custom("InterTight-Black", size: family == .systemSmall ? 30 : 24))
            .tracking(-1)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: person.color))
            .accessibilityLabel("Send \(person.name) a Psst")
    }

    private func message(_ text: String, url: String) -> some View {
        VStack(spacing: 6) {
            Text("psst")
                .font(.custom("InterTight-Black", size: 28))
                .tracking(-1)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: url))
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
