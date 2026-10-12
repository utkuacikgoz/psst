import XCTest
@testable import Psst

@MainActor
final class HapticsTests: XCTestCase {
    func testPsstPatternMatchesTheWhisper() throws {
        let psst = try PsstHaptics.pattern(for: .psst)
        XCTAssertEqual(psst.duration, 0.46, accuracy: 0.05)
    }

    func testSuperPsstPlaysItTwice() throws {
        let superPsst = try PsstHaptics.pattern(for: .superPsst)
        XCTAssertEqual(superPsst.duration, 1.08, accuracy: 0.05)
    }
}
