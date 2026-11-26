import Foundation
import JavaScriptCore
import Testing

/// Runs `Resources/web/screen.js` in JavaScriptCore: in a Home Screen web app the full-screen layers take the screen's
/// height, because iOS can leave the viewport short after the phone turns (design §8).
struct WebScreenTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        let url = WebPageTests.webDirectory.appendingPathComponent("screen.js")
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
    }

    /// `fullScreenHeight(standalone, landscape, screen.width, screen.height, innerWidth)` as text.
    func height(_ arguments: String) -> String? {
        context.evaluateScript("String(PhoneBox.fullScreenHeight(\(arguments)))")?.toString()
    }

    @Test func aHomeScreenAppTakesTheScreensHeightInBothOrientations() {
        // An iPhone 16 Pro Max: screen.width/height stay 430 × 932 when it turns.
        #expect(height("true, true, 430, 932, 932") == "430")
        #expect(height("true, false, 430, 932, 430") == "932")
    }

    @Test func aBrowserTabIsLeftToCSS() {
        #expect(height("false, true, 430, 932, 932") == "null")
    }

    @Test func aWindowNarrowerThanTheScreenIsLeftToCSS() {
        #expect(height("true, true, 430, 932, 700") == "null")
        #expect(height("true, true, 0, 0, 0") == "null")
    }
}
