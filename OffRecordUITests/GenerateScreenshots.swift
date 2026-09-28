//
//  GenerateScreenshots.swift
//  OffRecordUITests
//
//  Automated App Store screenshot generation.
//  Seeds realistic data via -ScreenshotMode launch argument (plus the photos and voice
//  clip in AppStore/seed-media), then navigates each screen and captures screenshots.
//
//  Usage (see AppStore/capture-screenshots.sh for the full device × appearance run):
//  xcodebuild test -scheme OffRecord \
//    -destination 'platform=iOS Simulator,name=OffRecord Shots 17 Pro Max' \
//    -only-testing:OffRecordUITests/ScreenshotTests \
//    -resultBundlePath ./screenshots.xcresult
//

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    private static let todayEntryID = "11111111-1111-1111-1111-111111111111"
    private static let weeklyReflectionID = "22222222-2222-2222-2222-222222222222"

    /// AppStore/seed-media in this checkout; the simulator app reads it straight from disk.
    private static let seedMediaPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("AppStore/seed-media", isDirectory: true)
        .path

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(route: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-ScreenshotMode",
            "-SemanticMemoryUseFallbackEmbeddings",
            "-hasCompletedOnboarding", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        if let route {
            app.launchArguments += ["-OpenRoute", route]
        }
        app.launchEnvironment["OFFRECORD_SCREENSHOT_MEDIA"] = Self.seedMediaPath
        app.launch()
    }

    // MARK: - Screenshots

    func test01_Today() throws {
        launch()
        tapOffRecordTab("today", in: app)
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 10))
        takeScreenshot(named: "01_Today")
    }

    func test02_Recording() throws {
        launch()
        tapOffRecordTab("today", in: app)
        let record = app.buttons["todayDock.record"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.panel"].firstMatch.waitForExistence(timeout: 8))
        takeScreenshot(named: "02_Recording")
    }

    func test03_Timeline() throws {
        launch()
        tapOffRecordTab("timeline", in: app)
        XCTAssertTrue(app.searchFields["timeline.searchField"].firstMatch.waitForExistence(timeout: 10))
        takeScreenshot(named: "03_Timeline")
    }

    func test04_Search() throws {
        launch(route: "offrecord://timeline?query=Sarah")
        XCTAssertTrue(app.searchFields["timeline.searchField"].firstMatch.waitForExistence(timeout: 10))
        dismissKeyboardIfNeeded(in: app)
        takeScreenshot(named: "04_Search")
    }

    func test05_EntryDetail() throws {
        launch(route: "offrecord://entry/\(Self.todayEntryID)")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "maples are just starting")).firstMatch.waitForExistence(timeout: 10))
        takeScreenshot(named: "05_EntryDetail")
    }

    func test05b_EntryPhotos() throws {
        launch(route: "offrecord://entry/\(Self.todayEntryID)")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "maples are just starting")).firstMatch.waitForExistence(timeout: 10))
        app.swipeUp(velocity: .slow)
        takeScreenshot(named: "05b_EntryPhotos")
    }

    func test06_Insights() throws {
        launch()
        tapOffRecordTab("insights", in: app)
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 10))
        takeScreenshot(named: "06_Insights")
    }

    func test07_WeeklyReflection() throws {
        launch(route: "offrecord://weekly-reflection/\(Self.weeklyReflectionID)")
        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 10))
        takeScreenshot(named: "07_WeeklyReflection")
    }

    func test08_Friday() throws {
        launch()
        tapOffRecordTab("friday", in: app)
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 10))
        takeScreenshot(named: "08_Friday")
    }

    func test09_FridayChat() throws {
        let question = "What helps me when work gets stressful?"
        let encoded = question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? question
        let route = URL(string: "offrecord://friday?question=\(encoded)")!
        launch()
        tapOffRecordTab("friday", in: app)
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 10))

        // Semantic memory builds right after seeding; ask again until Friday answers from it.
        let answer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "friday.answerMessage."))
            .firstMatch
        let stillIndexing = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "still building")).firstMatch
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 4)
            app.open(route)
            XCTAssertTrue(answer.waitForExistence(timeout: 20))
            guard stillIndexing.exists else { break }
            app.buttons["friday.backButton"].firstMatch.tap()
        }
        XCTAssertFalse(stillIndexing.exists, "Friday was still indexing")
        dismissKeyboardIfNeeded(in: app)
        takeScreenshot(named: "09_FridayChat")
    }

    func test10_FridayEmotions() throws {
        launch()
        tapOffRecordTab("friday", in: app)
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 10))
        openFridaySection("Emotions")
        XCTAssertTrue(app.staticTexts["Emotional Signature"].firstMatch.waitForExistence(timeout: 6))
        takeScreenshot(named: "10_FridayEmotions")
    }

    func test11_FridayWorld() throws {
        launch()
        tapOffRecordTab("friday", in: app)
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 10))
        openFridaySection("My World")
        takeScreenshot(named: "11_FridayWorld")
    }

    func test12_Settings() throws {
        launch()
        tapOffRecordTab("settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        takeScreenshot(named: "12_Settings")
    }

    // MARK: - Helpers

    /// Friday's section picker scrolls horizontally on iPhone, so later sections may start off-screen.
    private func openFridaySection(_ title: String) {
        let section = app.buttons["\(title) section"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        if !section.isHittable {
            app.buttons["Emotions section"].firstMatch.swipeLeft()
        }
        section.tap()
    }

    private func takeScreenshot(named name: String) {
        // Let entrance animations and image decoding settle.
        Thread.sleep(forTimeInterval: 1.5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
