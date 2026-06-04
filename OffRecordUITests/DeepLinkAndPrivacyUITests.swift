import XCTest

@MainActor
final class DeepLinkAndPrivacyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTimelineDeepLinkAppliesSearchQuery() throws {
        let app = launchRoutedApp(
            route: "offrecord://timeline?query=stress",
            arguments: semanticMemoryArguments
        )

        XCTAssertTrue(app.searchFields["timeline.searchField"].firstMatch.waitForExistence(timeout: 10))
        let value = app.searchFields["timeline.searchField"].firstMatch.value as? String ?? ""
        XCTAssertTrue(value.localizedCaseInsensitiveContains("stress"))
    }

    func testFridayDeepLinkOpensChatWithQuestion() throws {
        let question = "What did I write about work stress?"
        let encodedQuestion = question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? question
        let app = launchRoutedApp(
            route: "offrecord://friday?question=\(encodedQuestion)",
            arguments: semanticMemoryArguments
        )

        XCTAssertTrue(app.descendants(matching: .any)["friday.askField"].firstMatch.waitForExistence(timeout: 10))
        let userMessage = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "friday.userMessage.")).firstMatch
        XCTAssertTrue(userMessage.waitForExistence(timeout: 8))
        XCTAssertTrue(userMessage.label.localizedCaseInsensitiveContains("work stress"))
    }

    func testWeeklyReflectionCurrentDeepLinkOpensReport() throws {
        let app = launchRoutedApp(
            route: "offrecord://weekly-reflection/current",
            arguments: weeklyReflectionArguments
        )

        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Your Week"].waitForExistence(timeout: 4) || app.staticTexts["Your Week in Review"].exists)
    }

    func testSystemSearchSettingsExposePrivacySafeControls() throws {
        let app = launchOffRecord(arguments: semanticMemoryArguments)
        tapOffRecordTab("settings", in: app)

        let section = app.descendants(matching: .any)["settings.systemSearch.section"].firstMatch
        scrollUntilVisible(section, in: app, maxSwipes: 8)
        XCTAssertTrue(section.waitForExistence(timeout: 8))

        let settingsSurface = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .joined(separator: " ")
            .lowercased()
        XCTAssertFalse(settingsSurface.contains("quarterly review"))
        XCTAssertFalse(settingsSurface.contains("maya reminded me"))
    }

    private var semanticMemoryArguments: [String] {
        [
            "-UITesting",
            "-SemanticMemoryUITest",
            "-SemanticMemoryUseFallbackEmbeddings"
        ]
    }

    private var weeklyReflectionArguments: [String] {
        [
            "-UITesting",
            "-WeeklyReflectionUITest"
        ]
    }

    private func launchRoutedApp(route: String, arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + [
            "-hasCompletedOnboarding",
            "YES",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
            "-OpenRoute",
            route
        ]
        app.launch()
        return app
    }

}
