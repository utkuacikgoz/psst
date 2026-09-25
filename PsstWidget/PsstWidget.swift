import SwiftUI
import WidgetKit

/// The home-screen widget (Psst+): your first people as colour bands. Tapping a
/// band opens Psst and sends that person a Psst, just like tapping it at home.
/// The app writes the list to the shared App Group (see WidgetBridge).
@main
struct PsstWidgetBundle: WidgetBundle {
    var body: some Widget { PeopleWidget() }
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
