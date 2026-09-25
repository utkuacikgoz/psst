import XCTest

/// Walks the live (account) screens against the scripted Debug-only backend
/// (`UITestAPI`) and attaches a screenshot of each state.
final class LiveScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private var sizeName: String {
        ProcessInfo.processInfo.environment["PSST_SIZE_LABEL"] ?? "default"
    }

    func testLiveTour() {
        let app = launch("tour")

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        shot("live-01-name")
        name.tap()
        name.typeText("Utku")
        // At large text sizes the keyboard's return key is also labelled "Continue";
        // either one submits the name.
        app.buttons["Continue"].firstMatch.tap()

        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        shot("live-02-notifications")
        notNow.tap()

        XCTAssertTrue(app.buttons["Ada"].waitForExistence(timeout: 10))
        wait(0.3)
        shot("live-03-home-receiving")
        wait(1.5)
        shot("live-04-home")

        app.buttons["Emre"].tap()
        wait(0.5)
        shot("live-05-sending")
        wait(1.4)
        shot("live-06-sent")

        app.buttons["Sam"].tap()
        wait(1.2)
        shot("live-07-not-sent")

        app.buttons["Invite someone"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Create invite"].waitForExistence(timeout: 5))
        wait(0.4)
        shot("live-10-invite")
        app.buttons["Create invite"].tap()
        wait(0.8)
        shot("live-11-invite-created")
        let code = app.textFields["Invite code"]
        code.tap()
        code.typeText("K7QX4MPA\n")
        wait(0.8)
        shot("live-12-invite-preview")
        app.buttons["Done"].tap()
        wait(0.6)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        wait(0.6)
        shot("live-13-settings")

        app.buttons["Manage Ada"].tap()
        XCTAssertTrue(app.buttons["Remove Ada"].waitForExistence(timeout: 5))
        wait(0.6)
        shot("live-08-person")
    }

    func testLiveEmpty() {
        let app = launch("empty")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        wait(0.8)
        shot("live-14-empty")
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-PsstUITestLive", scenario]
        app.launch()
        return app
    }

    private func wait(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ step: String) {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(device) · \(sizeName) · \(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
