import XCTest

final class FeatureScreenshotTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments += ["-PsstUITestLive", scenario]; app.launch(); return app
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRecoveryStates() {
        var app = launch("loadFailure")
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 15))
        shot("recovery-home")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.buttons["Ada"].waitForExistence(timeout: 10))
        app.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-PsstUITestLive", "settingsFailure", "-PsstDesignScreen", "settings"]
        app.launch()
        let retry = app.buttons["Couldn't load blocked people. Try again"]
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No one."].exists)
        shot("recovery-settings")
        retry.tap()
        XCTAssertTrue(app.staticTexts["No one."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Couldn't load invites. Try again"].exists)
        app.terminate()

    }

    func testFeatureIntroduction() {
        let app = launch("returning")
        XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 15))
        shot("features-01-introduction")
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.buttons["Ada"].waitForExistence(timeout: 5))
    }
    func testFeatureScreens() {
        let app = launch("features")
        XCTAssertTrue(app.buttons["Ada"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 3)
        shot("features-02-home")
        app.buttons["Invite someone"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Share my invite"].waitForExistence(timeout: 5))
        shot("features-03-invite")
        app.buttons["Close"].tap()
        app.buttons["Emre"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Super Psst…"].waitForExistence(timeout: 5))
        shot("features-04-menu")
        app.buttons["Super Psst…"].tap()
        XCTAssertTrue(app.buttons["Send Super Psst"].waitForExistence(timeout: 5))
        shot("features-05-super")
        app.buttons["Send Super Psst"].tap()
        Thread.sleep(forTimeInterval: 4)
        app.buttons["Emre"].press(forDuration: 1)
        app.buttons["Super Psst…"].tap()
        XCTAssertTrue(app.staticTexts["Used for today"].waitForExistence(timeout: 5))
        shot("features-06-used")
        app.buttons["Close"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Your Psst activity"].waitForExistence(timeout: 5))
        shot("features-07-settings")
        app.buttons["Your Psst activity"].tap()
        XCTAssertTrue(app.staticTexts["Most sent to"].waitForExistence(timeout: 5))
        shot("features-08-activity-sent")
        app.buttons["Received from"].tap()
        shot("features-09-activity-received")
    }
    func testDesignReviewScreens() {
        captureScreens(["intro", "home", "invite", "activity", "super", "settings"])
    }
    func testFinalTypographyAdjustments() {
        captureScreens(["home", "activity", "code"])
    }
    private func captureScreens(_ screens: [String]) {
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments += ["-PsstUITestLive", "features", "-PsstDesignScreen", screen]
            app.launch()
            let expected: XCUIElement
            switch screen {
            case "intro": expected = app.buttons["Got it"]
            case "invite": expected = app.buttons["Share my invite"]
            case "activity": expected = app.staticTexts["Most sent to"]
            case "super": expected = app.buttons["Send Super Psst"]
            case "settings": expected = app.buttons["Your Psst activity"]
            case "code": expected = app.textFields["Invite code"]
            default: expected = app.buttons["Ada"]
            }
            if screen == "activity" {
                for _ in 0..<3 where !expected.exists { app.swipeUp() }
            }
            XCTAssertTrue(expected.waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: screen == "home" ? 3 : 0.6)
            shot("review-\(screen)")
            app.terminate()
        }
    }
    func testLongPressSuperEntryAndOneTapPsst() {
        let app = launch("features")
        XCTAssertTrue(app.buttons["Ada"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 3)
        shot("review-home")
        app.buttons["Emre"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Super Psst…"].waitForExistence(timeout: 5))
        shot("review-long-press")
        app.buttons["Super Psst…"].tap()
        XCTAssertTrue(app.buttons["Send Super Psst"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 available today"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'for Emre'")).firstMatch.exists)
        shot("review-super")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Emre"].waitForExistence(timeout: 5))
        app.buttons["Emre"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Emre' AND value BEGINSWITH 'Sent,'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send Psst"].exists)
    }
    func testSuperArrival() {
        let app = launch("superArrival")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Super Psst from Ada'")).firstMatch.waitForExistence(timeout: 15))
        shot("features-10-super-arrival")
    }
}
