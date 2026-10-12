import XCTest
@testable import Psst

final class AccessibilityTests: XCTestCase {
    /// VoiceOver reads a name for every colour on offer, never "Colour 3".
    func testEveryBandColourHasASpokenName() {
        for hex in Personalization.palette {
            XCTAssertNotNil(Personalization.colourNames[hex], String(hex, radix: 16))
        }
        XCTAssertEqual(Set(Personalization.colourNames.values).count, Personalization.palette.count)
    }
}

final class ExchangeLineTests: XCTestCase {
    func testOnlyWordsAreLowercasedAfterSent() {
        XCTAssertEqual(PersonRow.lowercasedStart("Just now"), "just now")
        XCTAssertEqual(PersonRow.lowercasedStart("Yesterday"), "yesterday")
        XCTAssertEqual(PersonRow.lowercasedStart("12m ago"), "12m ago")
        XCTAssertEqual(PersonRow.lowercasedStart("Oct 3"), "Oct 3")
    }
}
