import XCTest

/// Walks every prototype state and attaches a screenshot of each.
/// CI runs this on a compact and a large iPhone; see .github/workflows/ios.yml.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testStandardText() {
        capture(sizeName: "standard", contentSize: nil)
    }

    func testAccessibilityText() {
        capture(sizeName: "ax-xxxl", contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
    }

    private func capture(sizeName: String, contentSize: String?) {
        let app = XCUIApplication()
        // Argument-domain defaults: start every run from the same favorite.
        app.launchArguments += ["-psst.demo-alex.favoriteSignal", "squeeze"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()

        let alex = app.buttons["Alex"]
        XCTAssertTrue(alex.waitForExistence(timeout: 10))
        shot("01-home", sizeName)

        alex.tap()
        wait(0.15)
        shot("02-home-effect", sizeName)
        wait(1)
        shot("03-home-after-tap", sizeName)

        app.buttons["Signal for Alex: Squeeze"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        wait(0.6)
        shot("04-picker", sizeName)
        app.buttons["Preview Oi"].tap()
        wait(0.1)
        shot("05-picker-preview", sizeName)
        app.buttons["Done"].tap()
        wait(0.6)

        app.buttons["View Alex's phone (simulated)"].tap()
        XCTAssertTrue(app.buttons["Your phone"].waitForExistence(timeout: 5))
        wait(0.5)
        shot("06-alex-incoming", sizeName)
        app.buttons["You"].tap()
        wait(1)
        shot("07-alex-tapped-back", sizeName)

        app.buttons["Your phone"].tap()
        wait(0.45)
        shot("08-home-reply-effect", sizeName)
        wait(1)
        shot("09-home-reply", sizeName)

        app.buttons["Invite someone"].tap()
        wait(0.8)
        shot("10-invite", sizeName)
    }

    private func wait(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ step: String, _ sizeName: String) {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(device) · \(sizeName) · \(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
