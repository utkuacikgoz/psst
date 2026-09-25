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
        // Ada's unseen Psst opens the full-screen arrival, which clears itself.
        wait(0.4)
        shot("live-03-arrival")
        wait(2.2)
        // Then the one-time tap-and-hold tip; tapping it only dismisses it.
        let tip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tip'")).firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        shot("live-04a-tip")
        tip.tap()
        wait(0.5)
        shot("live-04-home")

        // Answering Ada right after her Psst is a same moment.
        app.buttons["Ada"].tap()
        wait(0.7)
        shot("live-04b-same-moment")
        wait(3.0)

        app.buttons["Emre"].tap()
        wait(0.5)
        shot("live-05-sending")
        wait(1.4)
        shot("live-06-sent")

        app.buttons["Sam"].tap()
        wait(1.2)
        shot("live-07-not-sent")
        app.buttons["Sam"].tap()
        wait(1.2)
        shot("live-07b-paused")

        app.buttons["Emre"].press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Report Emre"].waitForExistence(timeout: 5))
        wait(0.4)
        shot("live-09-long-press")
        app.buttons["Report Emre"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        wait(0.3)
        shot("live-09b-report-confirm")
        app.alerts.firstMatch.buttons["Cancel"].tap()
        wait(0.6)

        app.buttons["Invite someone"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Share my invite"].waitForExistence(timeout: 5))
        wait(0.4)
        shot("live-10-invite")
        app.buttons["Share my invite"].tap()
        XCTAssertTrue(app.buttons["Share invite"].waitForExistence(timeout: 5))
        wait(0.4)
        shot("live-11-invite-created")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["I have a code"].waitForExistence(timeout: 5))
        app.buttons["I have a code"].tap()
        let code = app.textFields["Invite code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        code.typeText("K7QX4MPA\n")
        wait(0.8)
        shot("live-12-invite-preview")
        app.buttons["Connect with Kim"].tap()
        // The sheet closes and Kim gets the full-screen welcome.
        wait(1.0)
        shot("live-15-welcome")
        wait(2.4)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        wait(0.6)
        shot("live-13-settings")

        // At the largest text sizes the people are below the fold.
        let manageAda = app.buttons["Manage Ada"]
        for _ in 0..<4 where !manageAda.isHittable { app.swipeUp() }
        manageAda.tap()
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
