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

struct FeatureIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    MischiefCat().frame(width: 62, height: 52).frame(maxWidth: .infinity)
                    Text("A little more mischief.").font(.largeTitle.bold())
                    item("Make one count.", "Touch and hold a person for Super Psst. One daily; unlimited with Psst+.", symbol: "sparkles")
                    item("See your activity.", "Find your personal sent and received rankings in Settings.", symbol: "chart.bar")
                    item("Know when.", "Your latest exchange now includes its time.", symbol: "clock")
                    Button("Got it") { dismiss() }
                        .font(.headline).foregroundStyle(Color.psstCanvas)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }.padding(Tokens.sheetInset)
            }
            .foregroundStyle(.white)
            .background(Color.psstCanvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() }.tint(.white) } }
        }
    }
    private func item(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            Image(systemName: symbol).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title).font(.headline)
                Text(detail).font(.body).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct ActivityView: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rows: [ActivitySummary] = []
    @State private var received = false
    @State private var loading = true
    @State private var failed = false
    private var ranked: [ActivitySummary] {
        rows.filter { (received ? $0.receivedCount : $0.sentCount) > 0 }.sorted {
            let a = received ? $0.receivedCount : $0.sentCount
            let b = received ? $1.receivedCount : $1.sentCount
            return a == b ? $0.otherName.localizedStandardCompare($1.otherName) == .orderedAscending : a > b
        }
    }
    var body: some View {
        List {
            Section {
                if dynamicTypeSize.isAccessibilitySize {
                    directionPicker.pickerStyle(.inline)
                } else {
                    directionPicker.pickerStyle(.segmented)
                }
            } footer: { Text("Your exchanges over the last 30 days. Includes Super Pssts. Only you can see this.") }
            Section(received ? "Most received from" : "Most sent to") {
                if loading { ProgressView("Loading activity") }
                else if failed { Button("Couldn't load activity. Try again") { Task { await load() } } }
                else if ranked.isEmpty { Text("No exchanges yet. Your activity will appear here after you psst.").foregroundStyle(.secondary) }
                else {
                    ForEach(ranked) { row in
                        HStack {
                            Text(row.otherName)
                            Spacer()
                            Text("\(received ? row.receivedCount : row.sentCount)").monospacedDigit().foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Your Psst activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    private var directionPicker: some View {
        Picker("Rank by", selection: $received) {
            Text("Sent to").tag(false)
            Text("Received from").tag(true)
        }
    }
    private func load() async {
        loading = true; failed = false
        do { rows = try await store.api.activity() } catch { failed = true }
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
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MischiefCat().frame(width: 64, height: 54).frame(maxWidth: .infinity)
                        .listRowBackground(Color.psstCanvas)
                    Text("Super Psst for \(connection.otherName)")
                        .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("Double whisper.")
                        .font(.body).foregroundStyle(.secondary)
                }
                Section {
                    if loading { ProgressView("Checking today's allowance") }
                    else if failed { Button("Couldn't check. Try again") { Task { await load() } } }
                    else if let allowance {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let available = allowance.unlimited || allowance.remaining > 0 || context.date >= allowance.resetsAt
                            Text(allowance.unlimited ? "Unlimited Super Pssts" : (available ? "1 available today" : "Used for today"))
                                .font(.headline)
                            if !available {
                                Text("Next one: \(allowance.resetsAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Button("Send Super Psst") {
                                Task { await submit() }
                            }
                            .disabled(!available || LiveHomeView.isBusy(store.status(for: connection)) || {
                                if case .notSent = store.status(for: connection) { return true }
                                return LiveHomeView.isPaused(store.status(for: connection))
                            }())
                            .frame(minHeight: Tokens.minTouch)
                        }
                    }
                } footer: {
                    Text("Their sound settings still apply.")
                    switch store.status(for: connection) {
                    case .notSent: Text("Retry your pending Psst first.")
                    case .sending: Text("A Psst is already sending.")
                    case .paused: Text("A little breather. Try again shortly.")
                    default: EmptyView()
                    }
                    if verificationFailed { Text("Couldn't verify Psst+ for unlimited sends. Your free daily Super Psst is still available if unused. Try again.") }
                }
                if !purchases.isUnlocked {
                    Section { Button("Unlimited with Psst+") { showingPlus = true } }
                }
            }
            .navigationTitle("Super Psst")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .task(id: scenePhase) { if scenePhase == .active { await load() } }
        .sheet(isPresented: $showingPlus, onDismiss: { Task { await load() } }) { PsstPlusSheet() }
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
