import SwiftUI

/// One vector mark, shared by the invite, introduction and Super Psst arrival.
struct MischiefCat: View {
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
                    p.move(to: CGPoint(x: w * 0.27, y: h * 0.48))
                    p.addLine(to: CGPoint(x: w * 0.4, y: h * 0.53))
                    p.move(to: CGPoint(x: w * 0.61, y: h * 0.52))
                    p.addQuadCurve(to: CGPoint(x: w * 0.75, y: h * 0.47), control: CGPoint(x: w * 0.7, y: h * 0.44))
                    p.move(to: CGPoint(x: w * 0.47, y: h * 0.66))
                    p.addLine(to: CGPoint(x: w * 0.52, y: h * 0.71))
                    p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.66))
                }.stroke(Color.psstCanvas, style: StrokeStyle(lineWidth: max(2, w * 0.04), lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
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
                    item("Make one count", "Touch and hold someone for Super Psst. One a day, unlimited with Psst+.", symbol: "sparkles")
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
    @State private var rows: [ActivitySummary] = []
    @State private var direction: Direction = .sent
    @State private var allTime = true
    @State private var loading = true
    @State private var failed = false
    @ScaledMetric(relativeTo: .largeTitle) private var podiumName: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var podiumCount: CGFloat = 30

    private func count(_ row: ActivitySummary) -> Int {
        switch direction {
        case .sent: allTime ? row.sentAll : row.sentMonth
        case .received: allTime ? row.receivedAll : row.receivedMonth
        case .both: allTime ? row.sentAll + row.receivedAll : row.sentMonth + row.receivedMonth
        }
    }

    private var ranked: [ActivitySummary] {
        rows.filter { count($0) > 0 }.sorted {
            count($0) == count($1)
                ? $0.otherName.localizedStandardCompare($1.otherName) == .orderedAscending
                : count($0) > count($1)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                if loading {
                    ProgressView("Loading activity").frame(maxWidth: .infinity).padding(Tokens.Space.xl)
                } else if failed {
                    Button("Couldn't load activity. Try again") { Task { await load() } }
                        .frame(maxWidth: .infinity, minHeight: Tokens.minTouch)
                } else if ranked.isEmpty {
                    Text(allTime ? "No Pssts yet. Your leaderboard starts with your first one."
                                 : "No Pssts this month yet.")
                        .foregroundStyle(.secondary)
                        .padding(Tokens.Space.l)
                } else {
                    ForEach(Array(ranked.prefix(3).enumerated()), id: \.element.id) { index, row in
                        podiumBand(rank: index + 1, row: row)
                    }
                    ForEach(Array(ranked.dropFirst(3).enumerated()), id: \.element.id) { index, row in
                        listRow(rank: index + 4, row: row)
                        Divider().padding(.leading, Tokens.Space.l)
                    }
                }
                Text("Only you see this. Super Pssts count too. All time counts from 30 days before this update.")
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
        let range = Picker("Time", selection: $allTime) {
            Text("All time").tag(true)
            Text("This month").tag(false)
        }
        let who = Picker("Rank by", selection: $direction) {
            ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
        }
        VStack(spacing: Tokens.Space.s) {
            if dynamicTypeSize.isAccessibilitySize {
                range.pickerStyle(.inline)
                who.pickerStyle(.inline)
            } else {
                range.pickerStyle(.segmented)
                who.pickerStyle(.segmented)
            }
        }
    }

    /// First, second and third: their band, their colour, the count.
    private func podiumBand(rank: Int, row: ActivitySummary) -> some View {
        let scale: CGFloat = rank == 1 ? 1 : rank == 2 ? 0.85 : 0.75
        return HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
            Text("\(rank)")
                .font(.psst(.title3, weight: .black))
                .foregroundStyle(Color.onBandSoft)
            Text(row.otherName.uppercased())
                .bandTitle(row.otherName, size: podiumName * scale, tracking: Tokens.Band.titleTracking)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count(row))")
                .font(.psst(size: podiumCount * scale, weight: .black))
                .monospacedDigit()
        }
        .foregroundStyle(Color.onCanvas)
        .padding(.horizontal, Tokens.Space.l)
        .frame(maxWidth: .infinity, minHeight: 72 + 40 * scale)
        .background(Color(hex: personalization.colorHex(for: row.connectionId, name: row.otherName)))
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
        let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        do { rows = try await store.api.activity(monthStart: monthStart) } catch { failed = true }
        loading = false
    }
}

struct SuperPsstSheet: View {
    let connection: ConnectionSummary
    @Environment(LiveStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var allowance: SuperAllowance?
    @State private var loading = true
    @State private var failed = false
    @State private var verificationFailed = false
    @State private var showingPlus = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Personalization.self) private var personalization
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    private func isAvailable(at date: Date) -> Bool {
        guard let allowance else { return false }
        return allowance.unlimited || allowance.remaining > 0 || date >= allowance.resetsAt
    }

    private var sendBlocked: Bool {
        let status = store.status(for: connection)
        if case .notSent = status { return true }
        return LiveHomeView.isBusy(status) || LiveHomeView.isPaused(status)
    }

    /// Their band, full screen: the cat, SUPER PSST, how many you have, and one
    /// white band to send. Everything else is a single quiet line.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let available = isAvailable(at: context.date)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.psst(.body, weight: .semibold))
                        .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
                        .padding(.horizontal, Tokens.Space.l)
                }
                ScrollView {
                    VStack(spacing: Tokens.Space.l) {
                        MischiefCat().frame(width: 84, height: 68)
                        VStack(spacing: Tokens.Space.xs) {
                            Text("SUPER PSST")
                                .bandTitle("Super Psst", size: titleSize, tracking: Tokens.Band.titleTracking)
                                .accessibilityAddTraits(.isHeader)
                            Text("for \(connection.otherName)")
                                .font(.psst(.title3, weight: .bold))
                        }
                        .accessibilityElement(children: .combine)
                        allowanceLine(available: available)
                        notes
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Tokens.sheetInset)
                    .padding(.vertical, Tokens.Space.xl)
                    .frame(maxWidth: .infinity)
                }
                if !purchases.isUnlocked {
                    Button("Unlimited with Psst+") { showingPlus = true }
                        .font(.psst(.subheadline, weight: .bold))
                        .frame(minHeight: Tokens.minTouch)
                        .padding(.bottom, Tokens.Space.s)
                }
                Button { Task { await submit() } } label: {
                    Text("SEND SUPER PSST")
                        .font(.psst(.title3, weight: .black))
                        .tracking(Tokens.Band.labelTracking)
                        .foregroundStyle(Color(hex: bandHex))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.surface.opacity(available && !sendBlocked && !loading ? 1 : 0.4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!available || sendBlocked || loading)
                .accessibilityLabel("Send Super Psst")
            }
            .foregroundStyle(Color.onCanvas)
        }
        .background(Color(hex: bandHex).ignoresSafeArea())
        .presentationBackground(Color(hex: bandHex))
        .task(id: scenePhase) { if scenePhase == .active { await load() } }
        .sheet(isPresented: $showingPlus, onDismiss: { Task { await load() } }) { PsstPlusSheet() }
    }

    private var bandHex: UInt32 { personalization.colorHex(for: connection.id, name: connection.otherName) }

    @ViewBuilder private func allowanceLine(available: Bool) -> some View {
        if loading {
            ProgressView("Checking today's Super Psst").tint(.white)
        } else if failed {
            Button("Couldn't check. Try again") { Task { await load() } }
                .font(.psst(.body, weight: .bold))
                .frame(minHeight: Tokens.minTouch)
        } else if let allowance {
            VStack(spacing: Tokens.Space.xs) {
                Text(allowance.unlimited ? "Unlimited Super Pssts" : (available ? "1 available today" : "Used for today"))
                    .font(.psst(.headline, weight: .bold))
                if !available {
                    Text("Next one: \(allowance.resetsAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.psst(.subheadline, weight: .medium))
                        .foregroundStyle(Color.onBandSoft)
                }
            }
        }
    }

    @ViewBuilder private var notes: some View {
        VStack(spacing: Tokens.Space.xs) {
            switch store.status(for: connection) {
            case .notSent: Text("Retry your pending Psst first.")
            case .sending: Text("A Psst is already sending.")
            case .paused: Text("A little breather. Try again shortly.")
            default: EmptyView()
            }
            if verificationFailed {
                Text("Couldn't verify Psst+ for unlimited sends. Your free daily Super Psst still works if unused.")
            }
            Text("Their sound settings still apply.")
        }
        .font(.psst(.footnote, weight: .medium))
        .foregroundStyle(Color.onBandSoft)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func submit() async {
        // Recheck quota and purchase status at the action, rather than trusting an
        // allowance loaded minutes ago while this sheet was open.
        await load()
        guard let allowance, !failed, allowance.unlimited || allowance.remaining > 0 else { return }
        if store.sendSuper(connection) != nil { dismiss() }
    }
    private func load() async {
        loading = true; failed = false; verificationFailed = false
        if let proof = purchases.signedTransaction {
            do { try await store.api.verifyPlus(signedTransaction: proof) }
            catch { verificationFailed = true }
        }
        do { allowance = try await store.api.superAllowance() } catch { failed = true }
        loading = false
    }
}
