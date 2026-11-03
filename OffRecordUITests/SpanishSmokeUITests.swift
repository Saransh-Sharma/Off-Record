import XCTest

/// Launches OffRecord in Spanish and visits the main tabs, so a missing or
/// broken translation that crashes or hides a screen shows up in CI.
///
/// Set `SMOKE_SHOT_DIR` (pass `TEST_RUNNER_SMOKE_SHOT_DIR=<dir>` to
/// xcodebuild) to also write each screenshot there as a PNG.
@MainActor
final class SpanishSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainTabsLaunchInSpanish() throws {
        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-ScreenshotMode",
            "-SemanticMemoryUseFallbackEmbeddings",
            "-hasCompletedOnboarding", "YES",
        ]
        app.launchArguments += ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()

        // Tab titles come from the Spanish catalog, so finding them proves it loaded.
        tapTab("Hoy")
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["todayDock.record"].firstMatch.waitForExistence(timeout: 8))
        capture("01_Hoy")

        tapTab("Historial")
        XCTAssertTrue(app.searchFields["timeline.searchField"].firstMatch.waitForExistence(timeout: 10))
        capture("02_Historial")

        tapTab("Patrones")
        XCTAssertTrue(app.navigationBars["Patrones"].waitForExistence(timeout: 10))
        capture("03_Patrones")

        tapTab("Friday")
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 10))
        capture("04_Friday")

        tapTab("Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 10))
        capture("05_Ajustes")

        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Helpers

    /// Taps a native tab bar button by its Spanish title. Scrolling minimizes
    /// the tab bar, so swipe down to restore it if needed.
    private func tapTab(_ title: String) {
        dismissKeyboardIfNeeded(in: app)
        let tab = app.tabBars.buttons[title].firstMatch
        for _ in 0..<3 where !tab.waitForExistence(timeout: 4) {
            app.swipeDown()
        }
        XCTAssertTrue(tab.exists, "Missing tab \(title)")
        tab.tap()
    }

    private func capture(_ name: String) {
        // Let entrance animations settle before the screenshot.
        Thread.sleep(forTimeInterval: 1.5)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        add(attachment)

        guard let dir = ProcessInfo.processInfo.environment["SMOKE_SHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }
}
