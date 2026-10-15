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
        if #available(iOS 18.0, *) {
            PsstControl()
        }
    }
}

/// Lock Screen: one tap on your first person (the top of home).
struct FavouriteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PsstFavourite", provider: Provider(fetchesDoodle: false)) { entry in
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
    /// The newest doodle sent to you that you haven't answered (free, 4A).
    var doodle: WidgetDoodle? = nil
}

/// Mirrors LatestDoodle in the app, with the sender's colour looked up.
struct WidgetDoodle: Hashable {
    let senderName: String
    let color: UInt32
    let strokes: [[[Double]]]
}

struct Provider: TimelineProvider {
    /// The Lock Screen widget never shows a doodle, so it never asks the server.
    var fetchesDoodle = true

    private var defaults: UserDefaults? {
        (Bundle.main.object(forInfoDictionaryKey: "PSSTAppGroup") as? String).flatMap(UserDefaults.init(suiteName:))
    }

    private struct StoredDoodle: Decodable {
        let connectionId: UUID
        let senderName: String
        let doodle: [[[Double]]]
    }

    private func read(doodle fetched: PsstSender.FetchedDoodle?? = nil) -> Entry {
        let people = defaults?.data(forKey: "psst.widget.people")
            .flatMap { try? JSONDecoder().decode([WidgetPerson].self, from: $0) } ?? []
        let everyone = defaults?.data(forKey: "psst.widget.everyone")
            .flatMap { try? JSONDecoder().decode([WidgetPerson].self, from: $0) } ?? people
        // What the app saved, unless the widget just asked the server itself.
        let stored = defaults?.data(forKey: "psst.widget.doodle").flatMap { try? JSONDecoder().decode(StoredDoodle.self, from: $0) }
        let source: (UUID, String, [[[Double]]])? = switch fetched {
        case .some(.some(let doodle)): (doodle.connectionId, doodle.senderName, doodle.doodle)
        case .some(.none): nil
        case .none: stored.map { ($0.connectionId, $0.senderName, $0.doodle) }
        }
        let doodle = source.map { id, name, strokes in
            WidgetDoodle(senderName: name, color: everyone.first { $0.id == id }?.color ?? 0x713F93, strokes: strokes)
        }
        return Entry(people: people, unlocked: defaults?.bool(forKey: "psst.widget.unlocked") ?? false, doodle: doodle)
    }

    func placeholder(in context: Context) -> Entry {
        Entry(people: [WidgetPerson(id: UUID(), name: "Mia", color: 0x5F61AE)], unlocked: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the widget whenever the people or the doodle change. While
        // the app is closed, the widget also checks for a new doodle now and then.
        guard fetchesDoodle else { return completion(Timeline(entries: [read()], policy: .never)) }
        Task {
            // nil: couldn't ask (keep what the app saved); .some(nil): no doodle now.
            let fetched: PsstSender.FetchedDoodle??
            do { fetched = .some(try await PsstSender.latestDoodle()) } catch { fetched = nil }
            completion(Timeline(entries: [read(doodle: fetched)], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

struct PeopleView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var shown: [WidgetPerson] {
        Array(entry.people.prefix(family == .systemSmall ? 1 : 3))
    }

    var body: some View {
        if let doodle = entry.doodle, family == .systemSmall || family == .systemMedium {
            // 3B: a doodle someone drew for you, as a polaroid, until you psst them back.
            polaroid(doodle).widgetURL(URL(string: "psst://home"))
        } else if !entry.unlocked {
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

    private func polaroid(_ doodle: WidgetDoodle) -> some View {
        VStack(spacing: 4) {
            WidgetDoodleShape(strokes: doodle.strokes)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(10)
                .aspectRatio(1, contentMode: .fit)
                .background(Color(hex: doodle.color), in: RoundedRectangle(cornerRadius: 6))
            Text("from \(doodle.senderName)")
                .font(.custom("InterTight-Black", size: 12))
                .foregroundStyle(Color(hex: 0x241B2C))
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 6, trailing: 8))
        .background(Color(hex: 0xFBF6EA), in: RoundedRectangle(cornerRadius: 10))
        .rotationEffect(.degrees(-4))
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A doodle from \(doodle.senderName). Opens Psst.")
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

/// A doodle's strokes (points from 0 to 1) in a square. Mirrors DoodleShape in the app.
struct WidgetDoodleShape: Shape {
    let strokes: [[[Double]]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for stroke in strokes {
            let points = stroke.compactMap { $0.count == 2 ? CGPoint(x: rect.minX + $0[0] * rect.width, y: rect.minY + $0[1] * rect.height) : nil }
            guard let first = points.first else { continue }
            path.move(to: first)
            if points.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y)) }
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        return path
    }
}
