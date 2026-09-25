import SwiftUI

/// The single source of layout and colour values for the app. See DESIGN.md §2–3.
enum Tokens {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    static let controlRadius: CGFloat = 0
    static let minTouch: CGFloat = 44
    static let personRowMinHeight: CGFloat = 144
    static let sheetInset: CGFloat = 24

    /// Yo-style colour-band layout (DESIGN.md §3).
    enum Band {
        static let wordmarkSize: CGFloat = 40
        static let wordmarkTracking: CGFloat = -2
        /// Contact names and received signal titles; scaled with Dynamic Type by callers.
        static let titleSize: CGFloat = 52
        static let titleTracking: CGFloat = -2.2
        /// Signal names in the picker.
        static let optionTitleSize: CGFloat = 30
        static let optionTracking: CGFloat = -0.7
        static let optionMinHeight: CGFloat = 90
        static let labelTracking: CGFloat = 1
        static let verticalPadding: CGFloat = 32
        /// The darker "Change signal" bar under each person.
        static let barMinHeight: CGFloat = 56
        static let addBandMinHeight: CGFloat = 96
        static let headerControlHeight: CGFloat = 48
        static let pickerGlyphSize: CGFloat = 54
        static let pickerStageHeight: CGFloat = 80
        static let recipientGlyphSize: CGFloat = 64
        static let recipientStageHeight: CGFloat = 90
        /// Band colour while a finger is down. White text stays above 5:1.
        static let pressedOpacity = 0.72
    }

    /// 24 pt side inset, 20 pt on very narrow phones. Safe areas are excluded by the caller.
    static func sideInset(forWidth width: CGFloat) -> CGFloat {
        width < 360 ? 20 : 24
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Yo-inspired purple canvas.
    static let psstCanvas = Color(hex: 0x713F93)
    /// Main text on canvas.
    static let onCanvas = Color.white
    /// Secondary text on the purple canvas.
    static let onCanvasSecondary = Color.white.opacity(0.82)

    /// Raised person surface and sheets.
    static let surface = Color.white
    /// Pressed person surface. Ink on it stays above 13:1.
    static let surfacePressed = Color(hex: 0xEEE7F3)
    /// Inset areas inside sheets (preview stage, option rows).
    static let surfaceInset = Color(hex: 0xF5F0F7)
    /// Text and icons on white surfaces.
    static let ink = Color(hex: 0x292031)
    /// Secondary text on white surfaces.
    static let inkSecondary = Color(hex: 0x66586E)
}

extension Color {
    /// Stable name-derived colours: reordering contacts does not change their identity.
    static func personBand(_ name: String) -> Color {
        Color(hex: personBandHex(name))
    }

    static func personBandHex(_ name: String) -> UInt32 {
        let palette: [UInt32] = [0x2476AA, 0x187F69, 0xB34F2B, 0xAC3E68, 0x5F61AE]
        let seed = name.lowercased().unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[seed]
    }
    static let addBand = Color(hex: 0xB87500)
    /// Shade for the bar that follows a band (opens the picker, never sends).
    static let bandShade = Color.black.opacity(0.15)
}

extension Text {
    /// Oversized band titles wrap between words but never inside one: each word
    /// gets at most one line, and a word too wide for the band scales down instead.
    func bandTitle(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        let words = max(1, text.split(whereSeparator: \.isWhitespace).count)
        return font(.psst(size: size, weight: .black))
            .tracking(tracking)
            .lineLimit(words)
            .minimumScaleFactor(0.4)
    }
}

/// Inter Tight, the brand face shared with psstapp.fun. Bundled (SIL Open Font
/// License, Psst/Fonts/OFL-InterTight.txt) and registered in Config/Info.plist.
enum PsstFont {
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy: "InterTight-Black"
        case .bold: "InterTight-Bold"
        case .semibold: "InterTight-SemiBold"
        default: "InterTight-Medium"
        }
    }

    /// Point sizes at the default (Large) text size; Dynamic Type scales them.
    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

extension Font {
    /// The brand face at a text style, scaling with Dynamic Type.
    static func psst(_ style: Font.TextStyle = .body, weight: Font.Weight = .medium) -> Font {
        .custom(PsstFont.name(for: weight), size: PsstFont.size(for: style), relativeTo: style)
    }

    /// The brand face at a size the caller already scales (e.g. with @ScaledMetric).
    static func psst(size: CGFloat, weight: Font.Weight) -> Font {
        .custom(PsstFont.name(for: weight), fixedSize: size)
    }
}
