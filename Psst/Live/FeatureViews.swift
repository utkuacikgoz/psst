import SwiftUI

/// One vector mark, shared by the invite, introduction and Super Psst arrival.
struct MischiefCat: View {
    /// The eyes and mouth; the band's colour makes them read as cut-outs.
    var eyes: Color = .psstCanvas
    /// Happy closed eyes and a smile instead of the mischief look.
    var happy = false

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.12, y: h * 0.86))
                    p.addQuadCurve(to: CGPoint(x: w * 0.15, y: h * 0.3), control: CGPoint(x: w * 0.01, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.13, y: h * 0.05))
                    p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.24))
                    p.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.24), control: CGPoint(x: w * 0.52, y: h * 0.17))
                    p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.04))
                    p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.33))
                    p.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.86), control: CGPoint(x: w * 0.99, y: h * 0.55))
                    p.closeSubpath()
                }.fill(.white)
                Path { p in
                    if happy {
                        p.move(to: CGPoint(x: w * 0.26, y: h * 0.53))
                        p.addQuadCurve(to: CGPoint(x: w * 0.4, y: h * 0.53), control: CGPoint(x: w * 0.33, y: h * 0.43))
                        p.move(to: CGPoint(x: w * 0.61, y: h * 0.53))
                        p.addQuadCurve(to: CGPoint(x: w * 0.75, y: h * 0.53), control: CGPoint(x: w * 0.68, y: h * 0.43))
                        p.move(to: CGPoint(x: w * 0.44, y: h * 0.65))
                        p.addQuadCurve(to: CGPoint(x: w * 0.6, y: h * 0.65), control: CGPoint(x: w * 0.52, y: h * 0.75))
                    } else {
                        p.move(to: CGPoint(x: w * 0.27, y: h * 0.48))
                        p.addLine(to: CGPoint(x: w * 0.4, y: h * 0.53))
                        p.move(to: CGPoint(x: w * 0.61, y: h * 0.52))
                        p.addQuadCurve(to: CGPoint(x: w * 0.75, y: h * 0.47), control: CGPoint(x: w * 0.7, y: h * 0.44))
                        p.move(to: CGPoint(x: w * 0.47, y: h * 0.66))
                        p.addLine(to: CGPoint(x: w * 0.52, y: h * 0.71))
                        p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.66))
                    }
                }.stroke(eyes, style: StrokeStyle(lineWidth: max(2, w * 0.04), lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The cat in home's pull gaps (owner pick 2A, 14 Oct 2026): happy, waving a paw,
/// with a word under it. "I'm here!" above the bands, "Psst!" under the + band.
struct PullCat: View {
    let text: String
    /// The colour behind it, for the cat's eyes.
    var eyes: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waving = false

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            ZStack(alignment: .topTrailing) {
                MischiefCat(eyes: eyes, happy: true).frame(width: 52, height: 44)
                paw
                    .rotationEffect(.degrees(waving ? -22 : 12), anchor: .bottom)
                    .offset(x: 12, y: -4)
            }
            Text(text).font(.psst(.footnote, weight: .bold))
        }
        .foregroundStyle(Color.onCanvas)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true)) { waving = true }
        }
        .accessibilityHidden(true)
    }

    private var paw: some View {
        ZStack {
            Ellipse().fill(.white).frame(width: 15, height: 18)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(hex: 0xE9B4C6)).frame(width: 3, height: 3) }
            }
            .offset(y: -4)
            Ellipse().fill(Color(hex: 0xE9B4C6)).frame(width: 6, height: 5).offset(y: 2)
        }
    }
}

/// The same white cat in other moods (owner picks 1A 2A 3A 4B, 14 Oct 2026, from
/// Fevzi's ideas): sleepy under the version, peeking while home loads, sad when
/// Psst can't connect, startled when a Psst arrives. Drawn on a 100 × 90 grid,
/// like MischiefCat; the ears of `.startled` reach a little above the frame.
struct MoodCat: View {
    enum Mood { case sleepy, awake, peeking, sad, startled }
    let mood: Mood
    /// The colour behind the cat, for its eyes and mouth.
    var eyes: Color = .psstCanvas
    /// Moves the eyes sideways, -1…1 (the peeking cat looks around).
    var look: CGFloat = 0
    /// A thin edge so the white cat shows on a light page (3B, owner pick 16 Oct 2026).
    var outline: Color? = nil

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: w * x / 100, y: h * y / 100) }
            let line = StrokeStyle(lineWidth: max(1.5, w * 0.05), lineCap: .round, lineJoin: .round)
            ZStack {
                head(pt).fill(.white)
                if let outline { head(pt).stroke(outline, style: StrokeStyle(lineWidth: max(1, w * 0.035), lineJoin: .round)) }
                face(pt).stroke(eyes, style: line)
                if mood == .awake {
                    Circle().fill(eyes).frame(width: w * 0.1, height: w * 0.1).position(pt(68, 51))
                }
                if mood == .sad {
                    Ellipse().fill(Color(hex: 0x9FD3FF)).frame(width: w * 0.08, height: h * 0.13).position(pt(30, 62))
                }
                if mood == .startled {
                    ForEach([CGFloat(33), CGFloat(68)], id: \.self) { x in
                        Circle().fill(eyes).frame(width: w * 0.16, height: w * 0.16).position(pt(x, 50))
                        Circle().fill(.white).frame(width: w * 0.05, height: w * 0.05).position(pt(x + 2.5, 47))
                    }
                    Ellipse().fill(eyes).frame(width: w * 0.08, height: h * 0.11).position(pt(52, 70))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The stroked eyes and mouth (the startled cat's are filled shapes instead).
    private func face(_ pt: (CGFloat, CGFloat) -> CGPoint) -> Path {
        let dx: CGFloat = look * 3
        var p = Path()
        switch mood {
        case .sleepy, .awake:
            p.move(to: pt(26, 52)); p.addLine(to: pt(40, 52))
            if mood == .sleepy { p.move(to: pt(61, 52)); p.addLine(to: pt(75, 52)) }
            p.move(to: pt(48, 66)); p.addLine(to: pt(52, 69)); p.addLine(to: pt(56, 66))
        case .peeking:
            p.move(to: pt(27 + dx, 48)); p.addLine(to: pt(40 + dx, 53))
            p.move(to: pt(61 + dx, 52)); p.addQuadCurve(to: pt(75 + dx, 47), control: pt(70 + dx, 44))
            p.move(to: pt(47, 66)); p.addLine(to: pt(52, 71)); p.addLine(to: pt(57, 66))
        case .sad:
            p.move(to: pt(26, 50)); p.addQuadCurve(to: pt(40, 48), control: pt(33, 52))
            p.move(to: pt(61, 48)); p.addQuadCurve(to: pt(75, 50), control: pt(68, 52))
            p.move(to: pt(44, 72)); p.addQuadCurve(to: pt(60, 72), control: pt(52, 64))
        case .startled:
            break
        }
        return p
    }

    /// The head: ears up for a startled cat, down for a sad one.
    private func head(_ pt: (CGFloat, CGFloat) -> CGPoint) -> Path {
        let (leftEar, rightEar): (CGPoint, CGPoint) = switch mood {
        case .startled: (pt(9, -4), pt(93, -5))
        case .sad: (pt(2, 16), pt(99, 15))
        default: (pt(13, 5), pt(88, 4))
        }
        return Path { p in
            p.move(to: pt(12, 86))
            p.addQuadCurve(to: pt(15, 30), control: pt(1, 55))
            p.addLine(to: leftEar)
            p.addLine(to: pt(38, 24))
            p.addQuadCurve(to: pt(65, 24), control: pt(52, 17))
            p.addLine(to: rightEar)
            p.addLine(to: pt(86, 33))
            p.addQuadCurve(to: pt(88, 86), control: pt(99, 55))
            p.closeSubpath()
        }
    }
}

/// A white paw with pink beans, as on the pull-gap cat.
struct CatPaw: View {
    var body: some View {
        ZStack {
            Ellipse().fill(.white).frame(width: 18, height: 15)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(hex: 0xE9B4C6)).frame(width: 3, height: 3) }
            }
            .offset(y: -3)
            Ellipse().fill(Color(hex: 0xE9B4C6)).frame(width: 6, height: 5).offset(y: 2)
        }
        .accessibilityHidden(true)
    }
}

/// 2A: home's loading cat. It peeks over a line with its paws on it and looks
/// left and right while your people load; with Reduce Motion it sits still.
struct LoadingCat: View {
    var eyes: Color = .psstCanvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var look: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            MoodCat(mood: .peeking, eyes: eyes, look: look)
                .frame(width: 72, height: 65)
                .offset(y: 16)
            HStack(spacing: 36) { CatPaw(); CatPaw() }
                .offset(y: 4)
        }
        .frame(width: 120, height: 80)
        .clipped()
        .overlay(alignment: .bottom) { Rectangle().fill(Color.onCanvas.opacity(0.5)).frame(height: 3) }
        .task {
            guard !reduceMotion else { return }
            for side in [CGFloat(-1), 1, 0].cycled() {
                withAnimation(.easeInOut(duration: 0.35)) { look = side }
                try? await Task.sleep(for: .milliseconds(side == 0 ? 1100 : 700))
                if Task.isCancelled { return }
            }
        }
        .accessibilityHidden(true)
    }
}

private extension Array {
    /// The elements over and over, for a looping animation.
    func cycled() -> AnySequence<Element> {
        AnySequence { () -> AnyIterator<Element> in
            var index = 0
            return AnyIterator {
                guard !self.isEmpty else { return nil }
                defer { index = (index + 1) % self.count }
                return self[index]
            }
        }
    }
}

/// 3A: the sad cat (ears down, one tear) shown where Psst can't connect.
struct SadCat: View {
    var eyes: Color = .psstCanvas
    var outline: Color? = nil
    var body: some View {
        MoodCat(mood: .sad, eyes: eyes, outline: outline).frame(width: 72, height: 65)
    }
}

/// The white cat on a light page (Settings, the leaderboard): grey face and a thin
/// grey edge, so it doesn't vanish into the background (3B). Dark pages unchanged.
struct LightPageCatColors {
    let eyes: Color
    let outline: Color?

    init(_ scheme: ColorScheme) {
        eyes = scheme == .light ? Color(.systemGray) : Color(.systemGroupedBackground)
        outline = scheme == .light ? Color(.systemGray3) : nil
    }
}

/// 4B: when a Psst arrives, a startled cat peeks in from the screen's edge, as if
/// someone just said psst behind it. With Reduce Motion it is simply there.
struct StartledPeekCat: View {
    /// The band's colour, for its eyes.
    var eyes: Color
    var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MoodCat(mood: .startled, eyes: eyes)
            .frame(width: 74, height: 67)
            .rotationEffect(.degrees(-24))
            .offset(x: shown || reduceMotion ? 14 : 110)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6).delay(0.15), value: shown)
            .accessibilityHidden(true)
    }
}

/// The Super Psst mark (owner pick 1A, 14 Oct 2026): the cat between two pairs of
/// "shake" arcs, Psst's own nudge. About twice as wide as it is tall.
struct NudgeMark: View {
    /// The band's colour, for the cat's eyes.
    var eyes: Color

    var body: some View {
        GeometryReader { geometry in
            let h = geometry.size.height
            let arcs = StrokeStyle(lineWidth: max(1.5, h * 0.07), lineCap: .round)
            HStack(spacing: h * 0.08) {
                ShakeArcs(mirrored: false).stroke(Color.white, style: arcs).frame(width: h * 0.36)
                MischiefCat(eyes: eyes).frame(width: h * 1.1, height: h)
                ShakeArcs(mirrored: true).stroke(Color.white, style: arcs).frame(width: h * 0.36)
            }
            .frame(width: geometry.size.width, height: h)
        }
        .accessibilityHidden(true)
    }
}

/// Two "shake" arcs beside the cat: the inner one short, the outer one taller.
struct ShakeArcs: Shape {
    /// The right-hand pair, opening the other way.
    var mirrored: Bool

    func path(in rect: CGRect) -> Path {
        func x(_ fraction: CGFloat) -> CGFloat { rect.minX + rect.width * (mirrored ? 1 - fraction : fraction) }
        func y(_ fraction: CGFloat) -> CGFloat { rect.minY + rect.height * fraction }
        var p = Path()
        p.move(to: CGPoint(x: x(0.85), y: y(0.24)))
        p.addQuadCurve(to: CGPoint(x: x(0.85), y: y(0.74)), control: CGPoint(x: x(0.45), y: y(0.49)))
        p.move(to: CGPoint(x: x(0.35), y: y(0.15)))
        p.addQuadCurve(to: CGPoint(x: x(0.35), y: y(0.83)), control: CGPoint(x: x(-0.05), y: y(0.49)))
        return p
    }
}

enum ExchangeTime {
    static func label(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// What's new, for people who already had Psst (new people get the tap tip instead).
/// One way out: the white band at the bottom, or a swipe down.
struct FeatureIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    MischiefCat().frame(width: 62, height: 52)
                    Text("A little more mischief")
                        .font(.psst(size: titleSize, weight: .black))
                        .tracking(Tokens.Band.titleTracking)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    item("Make one count", "Tap the cat on a band for Super Psst. One a day, unlimited with Psst+.", symbol: "sparkles")
                    item("Your activity", "Who you psst most, and who pssts you, in Settings. Only you see it.", symbol: "chart.bar.fill")
                    item("Know when", "Each band shows your latest exchange and when it was.", symbol: "clock.fill")
                }
                .padding(Tokens.sheetInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { dismiss() } label: {
                Text("Got it")
                    .font(.psst(.body, weight: .bold))
                    .foregroundStyle(Color.psstCanvas)
                    .frame(maxWidth: .infinity, minHeight: Tokens.Band.barMinHeight)
                    .background(Color.surface)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.onCanvas)
        .background(Color.psstCanvas.ignoresSafeArea())
        .presentationBackground(Color.psstCanvas)
    }

    private func item(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            Image(systemName: symbol)
                .font(.psst(.body, weight: .bold))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title).font(.psst(.headline, weight: .bold))
                Text(detail)
                    .font(.psst(.body))
                    .foregroundStyle(Color.onCanvasSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Your private leaderboard (owner pick, 12 Oct 2026): the top three as big bands
/// in their own colours, everyone else in a list. All time or this month; sent,
/// received or both. Only you see it.
struct ActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    enum Direction: String, CaseIterable, Identifiable {
        case sent = "Sent to", received = "Received from", both = "Both"
        var id: String { rawValue }
        var heading: String {
            switch self {
            case .sent: "Most sent to"
            case .received: "Most received from"
            case .both: "Most exchanged with"
            }
        }
    }

    @Environment(LiveStore.self) private var store
    @Environment(Personalization.self) private var personalization
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var direction: Direction = .sent
    @State private var loading = false
    @State private var failed = false
    /// False until the first refresh finishes, so an empty cache shows Loading, not "No Pssts yet".
    @State private var attempted = false
    @ScaledMetric(relativeTo: .largeTitle) private var podiumName: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var podiumCount: CGFloat = 30
    @ScaledMetric(relativeTo: .title3) private var podiumRank: CGFloat = 18

    private func count(_ row: ActivitySummary) -> Int {
        switch direction {
        case .sent: row.sentAll
        case .received: row.receivedAll
        case .both: row.sentAll + row.receivedAll
        }
    }

    private var ranked: [ActivitySummary] {
        store.activity.filter { count($0) > 0 }.sorted {
            count($0) == count($1)
                ? $0.otherName.localizedStandardCompare($1.otherName) == .orderedAscending
                : count($0) > count($1)
        }
    }

    /// Equal counts share a rank (1, 2, 2, 4), so a tie never looks like a loss.
    static func ranks(for counts: [Int]) -> [Int] {
        var result: [Int] = []
        for (index, value) in counts.enumerated() {
            result.append(index > 0 && value == counts[index - 1] ? result[index - 1] : index + 1)
        }
        return result
    }

    var body: some View {
        let entries = ranked
        let ranks = Self.ranks(for: entries.map { count($0) })
        ScrollView {
            // Lazy: only the rows on screen are built, however many people there are.
            LazyVStack(alignment: .leading, spacing: 0) {
                controls
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.m)
                Text(direction.heading)
                    .font(.psst(.footnote, weight: .bold))
                    .tracking(Tokens.Band.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.bottom, Tokens.Space.s)
                    .accessibilityAddTraits(.isHeader)
                // The last leaderboard shows straight away; these only appear with nothing to show.
                if store.activity.isEmpty && (loading || !attempted) {
                    ProgressView("Loading activity").frame(maxWidth: .infinity).padding(Tokens.Space.xl)
                } else if store.activity.isEmpty && failed {
                    VStack(spacing: Tokens.Space.s) {
                        SadCat(eyes: LightPageCatColors(colorScheme).eyes, outline: LightPageCatColors(colorScheme).outline)
                        Button("Couldn't load activity. Try again") { Task { await load() } }
                            .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
                    }
                    .padding(.top, Tokens.Space.l)
                } else if entries.isEmpty {
                    Text("No Pssts yet. Your leaderboard starts with your first one.")
                        .foregroundStyle(.secondary)
                        .padding(Tokens.Space.l)
                } else {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, row in
                        podiumBand(rank: ranks[index], row: row)
                    }
                    ForEach(Array(entries.enumerated().dropFirst(3)), id: \.element.id) { index, row in
                        listRow(rank: ranks[index], row: row)
                        Divider().padding(.leading, Tokens.Space.l)
                    }
                }
                Text("Only you see this. Super Pssts count too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(Tokens.Space.l)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your Psst activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private var controls: some View {
        let who = Picker("Rank by", selection: $direction) {
            ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
        }
        if dynamicTypeSize.isAccessibilitySize {
            who.pickerStyle(.inline)
        } else {
            who.pickerStyle(.segmented)
        }
    }

    /// First, second and third: their band, their colour, the count. Since owner pick
    /// 1B (18 Oct 2026) all three are one size, the ranks sit in one column so every
    /// name starts on the same line, and long names wrap to the left.
    private func podiumBand(rank: Int, row: ActivitySummary) -> some View {
        HStack(alignment: .center, spacing: Tokens.Space.m) {
            Text("\(rank)")
                .font(.psst(.title3, weight: .black))
                .monospacedDigit()
                .foregroundStyle(Color.onBandSoft)
                .frame(minWidth: podiumRank, alignment: .leading)
            Text(row.otherName.uppercased())
                .font(.psst(size: podiumName * 0.85, weight: .black))
                .tracking(Tokens.Band.titleTracking)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count(row))")
                .font(.psst(size: podiumCount * 0.85, weight: .black))
                .monospacedDigit()
        }
        .foregroundStyle(Color.onCanvas)
        .padding(.horizontal, Tokens.Space.l)
        .padding(.vertical, Tokens.Space.m)
        .frame(maxWidth: .infinity, minHeight: 106)
        .background(Color(hex: personalization.homeColorHex(for: row.connectionId, name: row.otherName, among: store.orderedConnections)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank), \(row.otherName), \(count(row))")
    }

    private func listRow(rank: Int, row: ActivitySummary) -> some View {
        HStack(spacing: Tokens.Space.m) {
            Text("\(rank)").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 24, alignment: .leading)
            Text(row.otherName)
            Spacer()
            Text("\(count(row))").monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, Tokens.Space.l)
        .frame(minHeight: Tokens.minTouch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank), \(row.otherName), \(count(row))")
    }

    private func load() async {
        loading = true; failed = false
        do { try await store.refreshActivity() } catch { failed = true }
        loading = false
        attempted = true
    }
}

struct SuperPsstSheet: View {
    let connection: ConnectionSummary
    @Environment(LiveStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Personalization.self) private var personalization
    @State private var allowance: SuperAllowance?
    @State private var loading = true
    @State private var checkingPlus = false
    @State private var failed = false
    @State private var verificationFailed = false
    @State private var showingPlus = false
    /// This sheet sent a Super Psst and is waiting for the server's answer.
    @State private var sending = false
    /// Set once the server accepts: plays the Ps-st pulse, then the sheet closes.
    @State private var sentID: UUID?
    /// The card is as tall as what it shows (1B): measured, not a full page.
    @State private var contentHeight: CGFloat = 300
    @State private var footerHeight: CGFloat = 80
    @State private var bottomInset: CGFloat = 0
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var compactTitleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var plusTitleSize: CGFloat = 28

    /// Every state the sheet can show (owner pick: Direction A, 13 Oct 2026).
    private enum Mode: Equatable {
        case gone, sending, sent, superFailed, earlierFailed
        case paused(until: Date)
        case loading, couldntLoad, available, unlimited
        case used(resetsAt: Date)
    }

    private func mode(at date: Date) -> Mode {
        if sentID != nil { return .sent }
        if !store.connections.contains(where: { $0.id == connection.id }) { return .gone }
        switch store.status(for: connection) {
        case .sending: return .sending
        case .notSent(let signal): return signal == .superPsst ? .superFailed : .earlierFailed
        case .paused(_, let until) where until > date: return .paused(until: until)
        default: break
        }
        if loading { return .loading }
        guard let allowance, !failed else { return .couldntLoad }
        if allowance.unlimited { return .unlimited }
        return allowance.remaining > 0 || date >= allowance.resetsAt ? .available : .used(resetsAt: allowance.resetsAt)
    }

    /// A short card in their colour over home (owner pick 1B, 16 Oct 2026; was a full
    /// page): the cat, SUPER PSST for NAME, one status line and one white band. Each
    /// state changes only the status line and what the band does; when today's free
    /// one is used, a calm Psst+ block appears and the card grows to fit it.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let mode = mode(at: context.date)
            VStack(spacing: 0) {
                ScrollView {
                    content(mode, now: context.date)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Tokens.sheetInset)
                        .padding(.top, Tokens.Space.xl)
                        .padding(.bottom, Tokens.Space.l)
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                footer(mode, now: context.date)
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.bottom, Tokens.Space.m)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
            .foregroundStyle(Color.onCanvas)
            .background { PsstRipple(trigger: sentID) }
            .clipped()
        }
        .background(Color(hex: bandHex).ignoresSafeArea())
        .presentationBackground(Color(hex: bandHex))
        // Taller than the screen allows (huge text): iOS caps it and the middle scrolls.
        .presentationDetents([.height(contentHeight + footerHeight + bottomInset)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .task(id: scenePhase) { if scenePhase == .active { await load() } }
        .onChange(of: store.status(for: connection)) { _, status in statusChanged(status) }
        .onChange(of: purchases.isUnlocked) { _, unlocked in if unlocked { Task { await load() } } }
        .sheet(isPresented: $showingPlus, onDismiss: { Task { await load() } }) { PsstPlusSheet() }
    }

    private var bandHex: UInt32 { personalization.homeColorHex(for: connection.id, name: connection.otherName, among: store.orderedConnections) }
    private var name: String { connection.otherName }

    // MARK: Middle

    @ViewBuilder private func content(_ mode: Mode, now: Date) -> some View {
        switch mode {
        case .gone:
            VStack(spacing: Tokens.Space.l) {
                MischiefCat().frame(width: 84, height: 68).opacity(0.55)
                Text("\(name) isn't here any more".uppercased())
                    .bandTitle("\(name) isn't here any more", size: titleSize, tracking: Tokens.Band.titleTracking)
                    .accessibilityAddTraits(.isHeader)
                detail("They left or removed the connection. Your Super Psst wasn't used.")
            }
        case .used(let resetsAt) where !purchases.isUnlocked:
            VStack(spacing: Tokens.Space.m) {
                head(compact: true)
                statusLine("Used for today", detail: resetLine(resetsAt, now: now))
                plusOffer
                if let message = purchaseMessage { note(message) }
                note("Pssting, replies and invites are always free.")
            }
        default:
            VStack(spacing: Tokens.Space.l) {
                head(title: mode == .sent ? "SENT" : "SUPER PSST", dimmed: isDimmed(mode))
                middle(mode, now: now)
            }
        }
    }

    private func isDimmed(_ mode: Mode) -> Bool {
        switch mode {
        case .couldntLoad, .earlierFailed, .paused: true
        default: false
        }
    }

    private var purchaseMessage: String? {
        switch purchases.state {
        case .failed(let message): message
        case .pending: "Waiting for approval. Psst+ unlocks when it's approved."
        default: nil
        }
    }

    private func head(title: String = "SUPER PSST", dimmed: Bool = false, compact: Bool = false) -> some View {
        VStack(spacing: compact ? Tokens.Space.m : Tokens.Space.l) {
            MischiefCat().frame(width: compact ? 64 : 84, height: compact ? 52 : 68)
            VStack(spacing: Tokens.Space.xs) {
                Text(title)
                    .bandTitle(title.capitalized, size: compact ? compactTitleSize : titleSize, tracking: Tokens.Band.titleTracking)
                    .accessibilityAddTraits(.isHeader)
                Text("for \(name)")
                    .font(.psst(.title3, weight: .bold))
                if !compact {
                    Text("Double whisper.")
                        .font(.psst(.subheadline, weight: .medium))
                        .foregroundStyle(Color.onBandSoft)
                }
            }
        }
        .opacity(dimmed ? 0.55 : 1)
    }

    @ViewBuilder private func middle(_ mode: Mode, now: Date) -> some View {
        switch mode {
        case .available:
            sparkleLine("1 available today")
            if verificationFailed { couldntConfirm(stillFree: true) } else { soundNote }
        case .unlimited:
            VStack(spacing: Tokens.Space.xs) {
                sparkleLine("Unlimited Super Pssts")
                detail("With Psst+. Thank you.")
            }
            soundNote
        case .used(let resetsAt):
            // Psst+ bought on this phone but not confirmed yet: never offer it again.
            statusLine("Used for today", detail: resetLine(resetsAt, now: now))
            couldntConfirm(stillFree: false)
        case .loading:
            if checkingPlus {
                HStack(spacing: Tokens.Space.s) {
                    ProgressView().tint(Color.onCanvas)
                    Text("Checking Psst+…").font(.psst(.headline, weight: .bold))
                }
            } else {
                VStack(spacing: Tokens.Space.s) {
                    Capsule().fill(Color.onCanvas.opacity(0.25)).frame(width: 160, height: 14)
                        .modifier(SendingShimmer(active: true))
                        .accessibilityHidden(true)
                    note("Checking today's Super Psst…")
                }
            }
            soundNote
        case .couldntLoad:
            if store.isOffline {
                statusLine("You're offline", detail: "Super Psst needs a connection. Nothing was sent.")
            } else {
                statusLine("Couldn't reach Psst", detail: "Try again in a moment.")
            }
        case .sending:
            sparkleLine("Sending…").opacity(0.6)
        case .sent:
            note("Closing…")
        case .superFailed:
            statusLine("Didn't make it", detail: "Trying again won't use another Super Psst.")
        case .earlierFailed:
            statusLine("Your last Psst to \(name) didn't make it", detail: "Send that one first, then your Super Psst.")
        case .paused:
            statusLine("A little breather", detail: "You've pssted \(name) a lot this minute.")
        case .gone:
            EmptyView()
        }
    }

    /// The upgrade when today's free one is used: what it is, and that it's one purchase.
    private var plusOffer: some View {
        VStack(spacing: Tokens.Space.xs) {
            Text("PSST+")
                .bandTitle("Psst+", size: plusTitleSize, tracking: Tokens.Band.titleTracking)
            Text("Your word, unlimited Super Pssts, whisper sounds and widgets.")
                .font(.psst(.callout, weight: .bold))
            Text("One purchase. Yours for good. No subscription.")
                .font(.psst(.footnote, weight: .medium))
                .foregroundStyle(Color.onBandSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Tokens.Space.l)
        .padding(.horizontal, Tokens.sheetInset)
        .frame(maxWidth: .infinity)
        .background(Color.bandShade)
        .padding(.horizontal, -Tokens.sheetInset)
        .accessibilityElement(children: .combine)
    }

    /// Psst+ couldn't be confirmed: say so plainly, offer both fixes, never block the free one.
    private func couldntConfirm(stillFree: Bool) -> some View {
        VStack(spacing: Tokens.Space.xs) {
            Text("Couldn't confirm Psst+ just now.")
                .font(.psst(.callout, weight: .bold))
            Text(stillFree ? "Today's free Super Psst still works. Unlimited comes back once Psst+ is confirmed."
                           : "Unlimited comes back once Psst+ is confirmed.")
                .font(.psst(.footnote, weight: .medium))
                .foregroundStyle(Color.onBandSoft)
            HStack(spacing: Tokens.Space.l) {
                Button("Try again") { Task { await load() } }
                Button("Restore purchase") { Task { await purchases.restore(); await load() } }
            }
            .font(.psst(.subheadline, weight: .bold))
            .frame(minHeight: Tokens.minTouch)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Tokens.Space.m)
        .padding(.horizontal, Tokens.sheetInset)
        .frame(maxWidth: .infinity)
        .background(Color.bandShade)
        .padding(.horizontal, -Tokens.sheetInset)
    }

    private func statusLine(_ title: String, detail text: String?) -> some View {
        VStack(spacing: Tokens.Space.xs) {
            Text(title).font(.psst(.headline, weight: .bold))
            if let text { detail(text) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sparkleLine(_ text: String) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "sparkle").accessibilityHidden(true)
            Text(text)
        }
        .font(.psst(.headline, weight: .bold))
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.psst(.subheadline, weight: .medium))
            .foregroundStyle(Color.onBandSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.psst(.footnote, weight: .medium))
            .foregroundStyle(Color.onBandSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var soundNote: some View { note("Their sound settings still apply.") }

    /// "Next free one at 3:00 AM · in 6 h 12 m": a plain fact, never a purchase timer.
    private func resetLine(_ resetsAt: Date, now: Date) -> String {
        let minutes = max(1, Int(resetsAt.timeIntervalSince(now) / 60))
        let wait = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) m" : "\(minutes) m"
        return "Next free one at \(resetsAt.formatted(date: .omitted, time: .shortened)) · in \(wait)"
    }

    // MARK: Band

    @ViewBuilder private func footer(_ mode: Mode, now: Date) -> some View {
        VStack(spacing: 0) {
            switch mode {
            case .available:
                if !purchases.isUnlocked && !verificationFailed {
                    Button("Unlimited with Psst+") { showingPlus = true }
                        .font(.psst(.subheadline, weight: .bold))
                        .frame(minHeight: Tokens.minTouch)
                        .padding(.bottom, Tokens.Space.s)
                }
                band("SEND SUPER PSST", label: "Send Super Psst") { Task { await submit() } }
            case .unlimited:
                band("SEND SUPER PSST", label: "Send Super Psst") { Task { await submit() } }
            case .loading:
                band("SEND SUPER PSST", label: "Send Super Psst", enabled: false) {}
            case .used where !purchases.isUnlocked:
                band(unlockTitle, label: "Unlock Psst+", enabled: purchases.state != .purchasing,
                     sweeping: purchases.state == .purchasing) { unlock() }
                HStack(spacing: Tokens.Space.l) {
                    Button("Restore purchase") { Task { await purchases.restore(); await load() } }
                    Button("Send \(name) a Psst") { store.tap(connection); dismiss() }
                }
                .font(.psst(.subheadline, weight: .bold))
                .frame(minHeight: Tokens.minTouch)
                .padding(.top, Tokens.Space.xs)
            case .used, .couldntLoad, .superFailed:
                band("TRY AGAIN", label: "Try again") {
                    if mode == .superFailed {
                        // Same event ID: it can't send twice or use a second free one.
                        sending = true
                        store.tap(connection)
                    } else {
                        Task { await load() }
                    }
                }
            case .sending:
                band("SENDING…", label: "Sending", enabled: false, sweeping: true) {}
            case .sent:
                band("SUPER PSST SENT", label: "Super Psst sent") { dismiss() }
            case .earlierFailed:
                band("RETRY THAT PSST", label: "Retry that Psst") { store.tap(connection) }
            case .paused(let until):
                let seconds = max(0, Int(until.timeIntervalSince(now).rounded(.up)))
                band("TRY AGAIN IN \(seconds / 60):\(String(format: "%02d", seconds % 60))",
                     label: "Try again in \(seconds) seconds", enabled: false) {}
            case .gone:
                band("CLOSE", label: "Close") { dismiss() }
            }
        }
    }

    private var unlockTitle: String {
        purchases.displayPrice.map { "UNLOCK PSST+ · \($0)" } ?? "UNLOCK PSST+"
    }

    private func band(_ title: String, label: String, enabled: Bool = true, sweeping: Bool = false,
                      action: @escaping () -> Void) -> some View {
        // Paused (3A, owner pick 20 Oct 2026): an outlined button at full strength reads
        // as waiting and stays readable (the faded white one was about 2:1).
        let outlined = !enabled && !sweeping
        return Button(action: action) {
            Text(title)
                .font(.psst(.title3, weight: .black))
                .tracking(Tokens.Band.labelTracking)
                .foregroundStyle(outlined ? Color.white : Color(hex: bandHex))
                .modifier(SendingShimmer(active: sweeping))
                .padding(.horizontal, Tokens.Space.l)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(outlined ? Color.clear : Color.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    if outlined { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white, lineWidth: 2) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    /// Apple's purchase sheet straight from here; the full Psst+ sheet when the
    /// App Store product hasn't loaded (it shows why and offers Try again).
    private func unlock() {
        if purchases.product == nil {
            showingPlus = true
        } else {
            Task { await purchases.buy(accountID: store.api.accountID) }
        }
    }

    private func statusChanged(_ status: LiveRowStatus) {
        guard sending else { return }
        switch status {
        case .sending, .notSent:
            break // Still going, or "Didn't make it" with Try again.
        case .sent(.superPsst):
            sending = false
            sentID = UUID()
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                dismiss()
            }
        default:
            // Refused (today's one already used elsewhere) or paused: show the fresh state.
            sending = false
            Task { await load(showProgress: false) }
        }
    }

    private func submit() async {
        // Recheck quota and purchase status at the action, rather than trusting an
        // allowance loaded minutes ago while this sheet was open.
        await load(showProgress: false)
        guard let allowance, !failed, allowance.unlimited || allowance.remaining > 0 else { return }
        if store.sendSuper(connection) != nil { sending = true }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress { loading = true }
        failed = false
        verificationFailed = false
        if let proof = purchases.signedTransaction {
            checkingPlus = showProgress
            do { try await store.api.verifyPlus(signedTransaction: proof) }
            catch { verificationFailed = true }
            checkingPlus = false
        }
        do { allowance = try await store.api.superAllowance() } catch { failed = true }
        loading = false
    }
}

/// The Sunday recap (owner pick 4A, 14 Oct 2026), opened from its push: YOUR WEEK,
/// then a band for the total, your #1 in their colour, your longest streak, and a
/// white band to psst your #1. Only you see it.
struct WeeklyRecapView: View {
    @Environment(LiveStore.self) private var store
    @Environment(Personalization.self) private var personalization
    @Environment(\.dismiss) private var dismiss
    @State private var recap: WeeklyRecap?
    @State private var failed = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var bigSize: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .font(.psst(.body, weight: .semibold))
                    .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
                    .padding(.horizontal, Tokens.Space.l)
            }
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: Tokens.Space.xs) {
                        Text("YOUR WEEK")
                            .bandTitle("Your week", size: titleSize, tracking: Tokens.Band.titleTracking)
                            .accessibilityAddTraits(.isHeader)
                        if let recap { Text(recap.rangeLabel).font(.psst(.subheadline, weight: .semibold)) }
                    }
                    .padding(.bottom, Tokens.Space.l)
                    content
                }
                .multilineTextAlignment(.center)
            }
            .scrollBounceBehavior(.basedOnSize)
            if let top = recap?.top, let connection = store.connections.first(where: { $0.id == top.connectionId }) {
                Button {
                    store.tap(connection)
                    dismiss()
                } label: {
                    Text("PSST \(top.name.uppercased())")
                        .font(.psst(.title3, weight: .black))
                        .tracking(Tokens.Band.labelTracking)
                        .foregroundStyle(Color.psstCanvas)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Psst \(top.name)")
            }
        }
        .foregroundStyle(Color.onCanvas)
        .background(Color.psstCanvas.ignoresSafeArea())
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if let recap {
            if recap.total == 0 {
                Text("No Pssts this week yet.")
                    .font(.psst(.body, weight: .semibold))
                    .padding(Tokens.Space.xl)
            } else {
                band(color: .addBand) {
                    // 4A (owner pick, 16 Oct 2026): one Psst is "1 PSST".
                    Text(recap.total == 1 ? LocalizedStringKey("1 PSST") : "\(recap.total) PSSTS")
                        .bandTitle(recap.total == 1 ? "1 Psst" : "\(recap.total) Pssts", size: bigSize, tracking: Tokens.Band.titleTracking)
                    Text("\(recap.sent) sent · \(recap.received) received")
                        .font(.psst(.subheadline, weight: .semibold))
                }
                if let top = recap.top {
                    band(color: colour(top.connectionId, top.name)) {
                        Text(top.still ? "YOUR #1 · STILL" : "YOUR #1")
                            .font(.psst(.footnote, weight: .bold))
                            .tracking(Tokens.Band.labelTracking)
                        Text(top.name.uppercased())
                            .bandTitle(top.name, size: bigSize, tracking: Tokens.Band.titleTracking)
                        Text(top.count == 1 ? LocalizedStringKey("1 Psst this week") : "\(top.count) Pssts this week")
                            .font(.psst(.subheadline, weight: .semibold))
                    }
                }
                if let streak = recap.streak {
                    band(color: colour(streak.connectionId, streak.name)) {
                        Text("LONGEST STREAK")
                            .font(.psst(.footnote, weight: .bold))
                            .tracking(Tokens.Band.labelTracking)
                        HStack(spacing: Tokens.Space.s) {
                            Image(systemName: "flame.fill").font(.psst(size: bigSize * 0.6, weight: .black))
                            Text("\(streak.days) DAYS")
                                .bandTitle("\(streak.days) days", size: bigSize, tracking: Tokens.Band.titleTracking)
                        }
                        Text("with \(streak.name) · still going")
                            .font(.psst(.subheadline, weight: .semibold))
                    }
                }
            }
        } else if failed {
            VStack(spacing: Tokens.Space.s) {
                SadCat()
                Button("Couldn't load your week. Try again") { Task { await load() } }
                    .font(.psst(.body, weight: .bold))
                    .frame(minHeight: Tokens.minTouch)
            }
            .padding(Tokens.Space.xl)
        } else {
            ProgressView().tint(Color.onCanvas).padding(Tokens.Space.xl)
        }
    }

    private func band<Content: View>(color: Color, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Tokens.Space.xs) { content() }
            .padding(.vertical, Tokens.Space.xl)
            .padding(.horizontal, Tokens.Space.xl)
            .frame(maxWidth: .infinity)
            .background(color)
            .accessibilityElement(children: .combine)
    }

    private func colour(_ id: UUID, _ name: String) -> Color {
        Color(hex: personalization.homeColorHex(for: id, name: name, among: store.orderedConnections))
    }

    private func load() async {
        failed = false
        do { recap = try await store.api.weeklyRecap() } catch { failed = true }
    }
}
