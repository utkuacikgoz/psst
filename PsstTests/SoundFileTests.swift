import XCTest
@testable import Psst

/// A push names a sound file; if it isn't in the app, iOS silently plays its
/// default sound instead. Every sound the server can send must ship.
final class SoundFileTests: XCTestCase {
    func testEveryWhisperSoundShipsInTheApp() throws {
        let sounds = ["psst.wav", "psst-soft.wav", "psst-quick.wav",
                      "psst-double.wav", "psst-low.wav", "psst-long.wav"]
        for sound in sounds {
            let url = try XCTUnwrap(Bundle.main.url(forResource: sound, withExtension: nil), "\(sound) is missing from the app")
            let data = try Data(contentsOf: url)
            XCTAssertEqual(data.prefix(4), Data("RIFF".utf8), "\(sound) isn't a WAV file")
            XCTAssertGreaterThan(data.count, 10_000, "\(sound) is too short to hear")
        }
    }
}
