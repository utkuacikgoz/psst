import SwiftUI
import XCTest
@testable import Psst

@MainActor
final class BandColourTests: XCTestCase {
    private func personalization() -> Personalization {
        let defaults = UserDefaults(suiteName: "BandColourTests-\(UUID())")!
        return Personalization(defaults: defaults)
    }

    func testFirstFivePeopleGetFiveDifferentColours() {
        let colours = personalization()
        // Names whose old hash colours collide.
        let people = ["Ada", "Ada", "Ada", "Ada", "Ada"].map { (id: UUID(), name: $0) }
        colours.assignUsualColors(to: people)
        let hexes = Set(people.map { colours.colorHex(for: $0.id, name: $0.name) })
        XCTAssertEqual(hexes.count, 5)
    }

    func testUpdatingKeepsAColourThatWasAlreadyDistinct() {
        let colours = personalization()
        let mia = (id: UUID(), name: "Mia")
        colours.assignUsualColors(to: [mia])
        XCTAssertEqual(colours.colorHex(for: mia.id, name: mia.name), Color.personBandHex("Mia"))
    }

    func testNeighboursNeverShareAUsualColour() {
        let colours = personalization()
        let people = (0..<12).map { (id: UUID(), name: "P\($0)") }
        colours.assignUsualColors(to: people)
        let shown = colours.bandColors(for: people)
        for (above, below) in zip(people, people.dropFirst()) {
            XCTAssertNotEqual(shown[above.id], shown[below.id])
        }
    }

    func testAChosenColourIsNeverMoved() {
        let colours = personalization()
        let a = (id: UUID(), name: "A"), b = (id: UUID(), name: "B")
        colours.setColor(0x2B2B38, for: a.id)
        colours.setColor(0x2B2B38, for: b.id)
        let shown = colours.bandColors(for: [a, b])
        XCTAssertEqual(shown[a.id], 0x2B2B38)
        XCTAssertEqual(shown[b.id], 0x2B2B38)
    }
}
