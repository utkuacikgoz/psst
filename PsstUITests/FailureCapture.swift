import XCTest

extension XCTestCase {
    /// Attaches what was on screen when an assertion failed, so a CI run shows why.
    func attachFailureScreen(to issue: inout XCTIssue) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "failure · \(name.replacingOccurrences(of: " ", with: "_")) · line \(issue.sourceCodeContext.location?.lineNumber ?? 0)"
        attachment.lifetime = .keepAlways
        issue.add(attachment)
    }
}
