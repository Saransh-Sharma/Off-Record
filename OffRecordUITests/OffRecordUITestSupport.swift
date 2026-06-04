import XCTest

@MainActor
func launchOffRecord(arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments + [
        "-AppleLanguages",
        "(en)",
        "-AppleLocale",
        "en_US"
    ]
    app.launch()
    XCTAssertTrue(app.buttons["tab.today"].firstMatch.waitForExistence(timeout: 10))
    return app
}

@MainActor
func tapOffRecordTab(_ id: String, in app: XCUIApplication) {
    let tab = app.buttons["tab.\(id)"].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 8), "Missing tab.\(id)")
    tab.tap()
}

@MainActor
func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
    for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
        app.swipeUp()
    }
}

@MainActor
func waitForElement(_ element: XCUIElement, matching predicate: NSPredicate, timeout: TimeInterval = 5) -> Bool {
    guard element.waitForExistence(timeout: timeout) else { return false }
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
}

@MainActor
func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let expectation = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"),
        object: element
    )
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
}

extension XCUIElementQuery {
    func containingLabel(_ text: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label CONTAINS[c] %@", text))
    }
}
