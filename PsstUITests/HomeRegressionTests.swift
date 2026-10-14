import XCTest

/// Home must build its bands. 1.0.5 build 26 shipped a home whose lazy list built
/// nothing (a zero-height first row measuring the pull); this keeps it from returning.
final class HomeRegressionTests: XCTestCase {
    override func record(_ issue: XCTIssue) {
        var issue = issue
        attachFailureScreen(to: &issue)
        super.record(issue)
    }

    func testHomeBuildsBands() {
        let app = XCUIApplication()
        app.launchArguments += ["-PsstUITestLive", "store"]
        app.launch()
        _ = app.buttons["Psst from Mia"].waitForExistence(timeout: 10)
        _ = app.buttons["Psst from Mia"].waitForNonExistence(timeout: 12)

        XCTAssertTrue(app.buttons["Mia"].waitForExistence(timeout: 8), "Home built no bands")
        XCTAssertTrue(app.buttons["Invite someone"].firstMatch.exists, "Home built no + band")
        shot("home")
    }

    private func shot(_ step: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "home-regression · \(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
