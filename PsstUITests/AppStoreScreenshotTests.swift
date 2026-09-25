import XCTest

/// App Store screenshots: full-resolution captures of the live screens against
/// the Debug-only scripted backend (`-PsstUITestLive store`). Run on the largest
/// iPhone (6.9", 1320×2868) with a clean status bar; see the `appstore` option
/// of .github/workflows/ios.yml. The people are test fixtures.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAppStoreScreens() {
        let app = XCUIApplication()
        app.launchArguments += ["-PsstUITestLive", "store", "-PsstUITestHoldMoments"]
        app.launch()

        // Ada's Psst is waiting, so the app opens on her full-screen moment.
        // Wait for the moment itself: it only lasts about two seconds.
        // Moments are held for 8 s in this run (-PsstUITestHoldMoments).
        XCTAssertTrue(app.buttons["Psst from Ada"].waitForExistence(timeout: 15))
        wait(0.4)
        shot("01-arrival")

        let arrival = app.buttons["Psst from Ada"]
        XCTAssertTrue(arrival.waitForNonExistence(timeout: 12))
        wait(0.6)
        shot("02-home")

        // Answering right away is a same moment.
        app.buttons["Ada"].tap()
        wait(0.8)
        shot("03-same-moment")
        XCTAssertTrue(app.buttons["Invite someone"].firstMatch.waitForExistence(timeout: 12))
        wait(8.5)

        app.buttons["Invite someone"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Share my invite"].waitForExistence(timeout: 5))
        wait(0.5)
        shot("04-invite")

        app.buttons["I have a code"].tap()
        let code = app.textFields["Invite code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        code.typeText("K7QX4MPA\n")
        XCTAssertTrue(app.buttons["Connect with Kim"].waitForExistence(timeout: 5))
        app.buttons["Connect with Kim"].tap()
        wait(1.1)
        shot("05-welcome")
    }

    private func wait(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ step: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "appstore · 6.9 · \(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
