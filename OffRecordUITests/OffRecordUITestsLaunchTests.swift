//
//  OffRecordUITestsLaunchTests.swift
//  OffRecordUITests
//
//  Created by Karthikeyan NG on 01/12/25.
//

import XCTest

final class OffRecordUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-HeroNudgeUITest", "-HeroNudgeEmptyToday"]
        app.launch()

        XCTAssertTrue(offRecordTabButton("today", in: app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
