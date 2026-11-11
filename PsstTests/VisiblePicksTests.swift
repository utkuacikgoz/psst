import XCTest
@testable import Psst

/// 1.0.9 visible picks (owner picks, 10 Nov 2026): the pure logic behind 6A, 7A and 12A.
final class VisiblePicksTests: XCTestCase {
    /// 6A: a long single name gets hyphen points; the letters stay the same.
    func testLongNamesGetSoftHyphensBetweenLetters() {
        let hyphenated = Hyphenation.softHyphenated("Christopher", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(hyphenated.contains(Hyphenation.softHyphen), hyphenated)
        XCTAssertEqual(hyphenated.replacingOccurrences(of: Hyphenation.softHyphen, with: ""), "CHRISTOPHER")
    }

    /// 6A: every piece keeps at least two letters, so no "C- / HRISTOPHER".
    func testEveryPieceKeepsTwoLetters() {
        for name in ["Christopher", "Maximiliana", "Zzxqvbnmkl", "Bartholomew"] {
            let pieces = Hyphenation.segments(of: name, locale: Locale(identifier: "en_US"))
            XCTAssertEqual(pieces.joined(), name)
            XCTAssertGreaterThan(pieces.count, 1, name)
            for piece in pieces { XCTAssertGreaterThanOrEqual(piece.count, 2, "\(name): \(pieces)") }
        }
    }

    /// 6A: short names and names with spaces are left alone.
    func testShortNamesAndPhrasesAreLeftAlone() {
        XCTAssertEqual(Hyphenation.softHyphenated("Mia"), "MIA")
        XCTAssertEqual(Hyphenation.segments(of: "Mary Ann"), ["Mary Ann"])
    }

    /// 7A: only a Psst that didn't make it buzzes the error.
    func testOnlyNotSentIsAFailedSend() {
        XCTAssertTrue(LiveRowStatus.notSent(.psst).didNotSend)
        XCTAssertFalse(LiveRowStatus.sending(.psst).didNotSend)
        XCTAssertFalse(LiveRowStatus.paused(.psst, until: .now).didNotSend)
        XCTAssertFalse(LiveRowStatus.sent(.psst).didNotSend)
    }

    /// 12A: the "Pick yours" chip shows at most once a week.
    func testWordChipShowsAtMostOnceAWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(WordChip.isDue(lastShown: nil, now: now))
        XCTAssertFalse(WordChip.isDue(lastShown: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(WordChip.isDue(lastShown: now.addingTimeInterval(-6 * 86_400), now: now))
        XCTAssertTrue(WordChip.isDue(lastShown: now.addingTimeInterval(-7 * 86_400), now: now))
        XCTAssertTrue(WordChip.isDue(lastShown: now.addingTimeInterval(86_400), now: now), "a clock set back")
    }
}
