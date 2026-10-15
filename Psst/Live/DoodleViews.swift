import SwiftUI

/// A doodle (owner picks 1A 2A 3B 4A 5A, 15 Oct 2026): strokes of points from 0 to 1
/// in a square, drawn in white. The server checks the same limits.
typealias DoodleStrokes = [[[Double]]]

enum Doodle {
    static let maxStrokes = 60
    static let maxPoints = 2_000
}

/// The strokes as one path in a square of the given size.
struct DoodleShape: Shape {
    let strokes: DoodleStrokes

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

/// 3B: the doodle as a little cream polaroid, slightly tilted, "from Mia" underneath.
struct DoodlePolaroid: View {
    let strokes: DoodleStrokes
    let name: String
    let color: Color
    var width: CGFloat = 220

    var body: some View {
        VStack(spacing: width * 0.04) {
            DoodleShape(strokes: strokes)
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(2, width * 0.025), lineCap: .round, lineJoin: .round))
                .padding(width * 0.08)
                .frame(width: width * 0.88, height: width * 0.88)
                .background(color, in: RoundedRectangle(cornerRadius: width * 0.04))
            Text("from \(name)")
                .font(.psst(size: width * 0.075, weight: .bold))
                .foregroundStyle(Color(hex: 0x241B2C))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.top, width * 0.06)
        .padding(.horizontal, width * 0.06)
        .padding(.bottom, width * 0.09)
        .background(Color(hex: 0xFBF6EA), in: RoundedRectangle(cornerRadius: width * 0.06))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
        .rotationEffect(.degrees(-4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A doodle from \(name)")
    }
}

/// 1A: hold a band → Doodle for Mia. Draw with one finger in white on their colour,
/// then SEND DOODLE. Undo takes back the last stroke.
struct DoodleSheet: View {
    let connection: ConnectionSummary
    let color: Color

    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: DoodleStrokes = []
    @State private var current: [[Double]] = []
    @State private var refused = 0
    @State private var atLimit = false

    private var pointCount: Int { strokes.reduce(0) { $0 + $1.count } + current.count }

    var body: some View {
        VStack(spacing: Tokens.Space.m) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("To \(connection.otherName)").font(.psst(.body, weight: .bold))
                Spacer()
                Button("Undo") { if !strokes.isEmpty { strokes.removeLast(); atLimit = false } }
                    .disabled(strokes.isEmpty)
            }
            .font(.psst(.body, weight: .semibold))
            .frame(minHeight: Tokens.minTouch)

            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.12))
                    DoodleShape(strokes: strokes + (current.isEmpty ? [] : [current]))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    if strokes.isEmpty && current.isEmpty {
                        Text("Draw here").font(.psst(.headline, weight: .semibold)).opacity(0.6)
                    }
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in add(value.location, side: side) }
                        .onEnded { _ in
                            if !current.isEmpty, strokes.count < Doodle.maxStrokes { strokes.append(current) }
                            current = []
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Drawing area")
                .accessibilityHint("Draw with one finger.")
                // VoiceOver passes touches straight through, so the pad can be drawn on.
                .accessibilityAddTraits(.allowsDirectInteraction)
            }

            Button {
                // Nothing sent (a send to them is still going): keep the drawing open.
                if store.sendDoodle(connection, strokes: strokes) != nil { dismiss() } else { refused += 1 }
            } label: {
                Text("SEND DOODLE")
                    .font(.psst(.title3, weight: .black))
                    .tracking(Tokens.Band.labelTracking)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(strokes.isEmpty)
            .opacity(strokes.isEmpty ? 0.5 : 1)
            .sensoryFeedback(.error, trigger: refused)
            .sensoryFeedback(.warning, trigger: atLimit) { _, new in new }
        }
        .padding(Tokens.Space.l)
        .foregroundStyle(Color.onCanvas)
        .background(color.ignoresSafeArea())
        .presentationBackground(color)
    }

    /// Keeps points at least ~1% apart, within the limits, rounded to 3 decimals.
    private func add(_ location: CGPoint, side: CGFloat) {
        guard side > 0 else { return }
        guard pointCount < Doodle.maxPoints, strokes.count < Doodle.maxStrokes else {
            // The pen stops at the limit: one tap of feedback says so.
            atLimit = true
            return
        }
        let x = Double(min(max(location.x / side, 0), 1)), y = Double(min(max(location.y / side, 0), 1))
        let point: [Double] = [(x * 1000).rounded() / 1000, (y * 1000).rounded() / 1000]
        if let last = current.last, abs(last[0] - point[0]) + abs(last[1] - point[1]) < 0.01 { return }
        current.append(point)
    }
}
