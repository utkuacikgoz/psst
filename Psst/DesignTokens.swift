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
        // Slightly tight; tighter eats the gaps between words in Inter Tight Black.
        static let titleTracking: CGFloat = -0.5
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
    /// White labels exceed 11:1 contrast on the visible Super Psst action.
    static let superControl = Color(hex: 0x4D2868)
    /// Main text on canvas.
    static let onCanvas = Color.white
    /// Secondary text on the purple canvas. Solid white with Increase Contrast.
    static let onCanvasSecondary = Color(UIColor { traits in
        traits.accessibilityContrast == .high ? .white : UIColor.white.withAlphaComponent(0.82)
    })
    /// Small labels on bands. Solid white since owner pick 3A (20 Oct 2026): 90% white
    /// measured 4.1–4.5:1 on the gold, blue, green and rust bands, under the 4.5:1 guideline.
    static let onBandSoft = Color.white
    /// Placeholders on a shaded field (Search people over home, Draw here on the doodle
    /// pad). 16A (owner pick, 10 Nov 2026): 90% white is at least 4.6:1 on every band and
    /// the canvas (82% and 60% measured 4.2 and 3.1:1). Solid white with Increase Contrast.
    static let placeholderOnShade = Color(UIColor { traits in
        traits.accessibilityContrast == .high ? .white : UIColor.white.withAlphaComponent(0.9)
    })
    /// The NAME placeholder on a bare band (16A): 95% white is at least 4.6:1 on the
    /// usual band colours (55% measured 2.5–2.9:1).
    static let placeholderOnBand = Color(UIColor { traits in
        traits.accessibilityContrast == .high ? .white : UIColor.white.withAlphaComponent(0.95)
    })
    /// A quiet capsule behind small white text on a band (the arrival's "Pick yours"
    /// chip, 12A). Black at 20% keeps white text at 6.5:1 or more on every band colour,
    /// like the Edit name capsule (10A). Owner pick 2A on the follow-ups page, 11 Nov 2026.
    static let quietCapsule = Color.black.opacity(0.2)

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

    /// The usual band colours, in the order new people get them.
    static let personBandPalette: [UInt32] = [0x2476AA, 0xB34F2B, 0x187F69, 0xAC3E68, 0x5F61AE]

    /// The colour from a person's name, as before 1.0.3. Kept stable so updating
    /// doesn't recolour people whose colour was already distinct.
    static func personBandHex(_ name: String) -> UInt32 {
        let palette: [UInt32] = [0x2476AA, 0x187F69, 0xB34F2B, 0xAC3E68, 0x5F61AE]
        let seed = name.lowercased().unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[seed]
    }
    /// The one gold: the + band and the invite sheet. White text on it is 4.6:1.
    static let addBand = Color(hex: 0xA66700)
    static let inviteGold = addBand
    /// Shade for the bar that follows a band (opens the picker, never sends).
    static let bandShade = Color.black.opacity(0.15)
}

extension Text {
    /// Names and headlines in Inter Tight Black (DESIGN.md). Titles with spaces wrap
    /// at the requested text size instead of shrinking away the accessibility setting.
    /// A single word too wide for its band (owner pick 2A, 20 Oct 2026) shrinks to
    /// as little as 75% to stay whole, rather than breaking mid-word ("CHRISTOPHE / R").
    /// If it still doesn't fit, at any text size including the accessibility ones
    /// (owner pick 6A, 10 Nov 2026), it breaks with a hyphen: "CHRISTO- / PHER".
    func bandTitle(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        BandTitleText(text: self, word: text, size: size, tracking: tracking)
    }
}

private struct BandTitleText: View {
    let text: Text
    let word: String
    let size: CGFloat
    let tracking: CGFloat

    static let smallestScale: CGFloat = 0.75

    private var styled: Text { text.font(.psst(size: size, weight: .black)).tracking(tracking) }

    private var wrapping: some View {
        styled
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The word's width at full size, so the shrunk version can say how narrow it can go.
    private var naturalWidth: CGFloat {
        let font = UIFont(name: PsstFont.name(for: .black), size: size) ?? .systemFont(ofSize: size, weight: .black)
        let width = (word.uppercased() as NSString).size(withAttributes: [.font: font, .kern: tracking]).width
        return ceil(width)
    }

    /// The word with soft hyphens at its break points (6A). SwiftUI's Text breaks a
    /// line at a soft hyphen and draws a "-" there; where the line doesn't break, the
    /// soft hyphen stays invisible. (Text ignores NSParagraphStyle's hyphenationFactor,
    /// and iOS 17 has no hyphenation modifier, so the break points are put in the string.)
    private var hyphenated: some View {
        Text(verbatim: Hyphenation.softHyphenated(word))
            .font(.psst(size: size, weight: .black))
            .tracking(tracking)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        if word.contains(where: \.isWhitespace) {
            wrapping
        } else {
            // 2A, and since 6A at accessibility sizes too: whole on one line, then
            // shrunk to 75% at most, then broken with a hyphen.
            ViewThatFits(in: .horizontal) {
                styled.lineLimit(1)
                styled
                    .lineLimit(1)
                    .minimumScaleFactor(Self.smallestScale)
                    .frame(idealWidth: naturalWidth * Self.smallestScale)
                hyphenated
            }
            .multilineTextAlignment(.center)
        }
    }
}

/// Where a single word may break with a hyphen (owner pick 6A, 10 Nov 2026).
enum Hyphenation {
    static let softHyphen = "\u{00AD}"

    /// The word in capitals with a soft hyphen at each place it may break: the
    /// language's hyphenation points ("CHRIS·TO·PHER"), or, for a word the dictionary
    /// doesn't know, between any two letters. Each piece keeps at least two letters;
    /// words under five letters are left alone.
    static func softHyphenated(_ word: String, locale: Locale = .current) -> String {
        let pieces = segments(of: word, locale: locale)
        return pieces.map { $0.uppercased() }.joined(separator: softHyphen)
    }

    /// The word split at its break points, in its own letter case.
    static func segments(of word: String, locale: Locale = .current) -> [String] {
        let characters = Array(word)
        guard characters.count >= 5, !word.contains(where: \.isWhitespace) else { return [word] }
        let pieces = split(characters, at: dictionaryBreaks(in: word, locale: locale))
        guard pieces.count == 1, characters.allSatisfy(\.isLetter) else { return pieces }
        return split(characters, at: Array(2...(characters.count - 2)))
    }

    /// Pieces of at least two characters, cut at the given offsets where that allows.
    private static func split(_ characters: [Character], at offsets: [Int]) -> [String] {
        var pieces: [String] = []
        var start = 0
        for offset in offsets.sorted() where offset - start >= 2 && characters.count - offset >= 2 {
            pieces.append(String(characters[start..<offset]))
            start = offset
        }
        pieces.append(String(characters[start...]))
        return pieces
    }

    /// Character offsets before which the system's hyphenation dictionary allows a break.
    private static func dictionaryBreaks(in word: String, locale: Locale) -> [Int] {
        let english = Locale(identifier: "en_US")
        let chosen = CFStringIsHyphenationAvailableForLocale((locale as NSLocale) as CFLocale) ? locale : english
        guard CFStringIsHyphenationAvailableForLocale((chosen as NSLocale) as CFLocale) else { return [] }
        let string = word as NSString
        let length = string.length
        var breaks: [Int] = []
        var location = length
        while location > 0 {
            let found = CFStringGetHyphenationLocationBeforeIndex(string as CFString, location,
                                                                 CFRange(location: 0, length: length),
                                                                 0, (chosen as NSLocale) as CFLocale, nil)
            guard found != kCFNotFound, found > 0, found < location else { break }
            // UTF-16 offset → character offset; skip anything inside a character.
            let index = String.Index(utf16Offset: found, in: word)
            if index.samePosition(in: word) != nil {
                breaks.append(word.distance(from: word.startIndex, to: index))
            }
            location = found
        }
        return breaks
    }
}

/// Inter Tight, the brand face shared with psstapp.fun. Bundled (SIL Open Font
/// License, Psst/Fonts/OFL-InterTight.txt) and registered in Config/Info.plist.
enum PsstFont {
    static func name(for weight: Font.Weight) -> String {
        // Bold Text: the custom face doesn't thicken on its own, so step it up.
        switch UIAccessibility.isBoldTextEnabled ? bolder(weight) : weight {
        case .black, .heavy: "InterTight-Black"
        case .bold: "InterTight-Bold"
        case .semibold: "InterTight-SemiBold"
        default: "InterTight-Medium"
        }
    }

    private static func bolder(_ weight: Font.Weight) -> Font.Weight {
        switch weight {
        case .black, .heavy, .bold: .black
        case .semibold: .bold
        default: .semibold
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
