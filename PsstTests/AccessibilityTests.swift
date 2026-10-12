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
