import XCTest

/// Diagnostic: opens home with one 1.0.5 piece switched off at a time and records
/// whether the bands are built. Fails at the end with the full table.
final class HomeBisectTests: XCTestCase {
    func testHomeBisect() {
        let variants = ["none", "noTop", "noBottom", "noTop,noBottom", "noMeasure", "noBackground", "noCoord",
                        "noTop,noBottom,noMeasure,noBackground,noCoord"]
        var table: [String] = []
        for variant in variants {
            let app = XCUIApplication()
            app.launchArguments += ["-PsstUITestLive", "store", "-PsstHomeBisect", variant]
            app.launch()
            _ = app.buttons["Psst from Mia"].waitForExistence(timeout: 10)
            _ = app.buttons["Psst from Mia"].waitForNonExistence(timeout: 12)
            let built = app.buttons["Mia"].waitForExistence(timeout: 6)
            let plus = app.buttons["Invite someone"].firstMatch.exists
            Thread.sleep(forTimeInterval: 0.5)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "bisect · \(variant.replacingOccurrences(of: ",", with: "+")) · \(built ? "bands" : "blank")"
            attachment.lifetime = .keepAlways
            add(attachment)
            table.append("\(variant): bands=\(built) plus=\(plus)")
            app.terminate()
        }
        XCTFail("Home bisect results: " + table.joined(separator: " | "))
    }
}
