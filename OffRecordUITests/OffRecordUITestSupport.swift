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
    XCTAssertTrue(offRecordTabButton("today", in: app).firstMatch.waitForExistence(timeout: 10))
    return app
}

/// The native tab bar button for a tab id such as "today" or "timeline".
/// Falls back to the sidebar/any button with the tab's title on iPad layouts.
///
/// The native tab bar sits behind the keyboard, so an open keyboard is submitted
/// first. The app also exposes a hidden, zero-frame copy of each tab button, so
/// a bare `app.buttons[title].firstMatch` must never be used for tabs.
@MainActor
func offRecordTabButton(_ id: String, in app: XCUIApplication) -> XCUIElement {
    dismissKeyboardIfNeeded(in: app)
    let title = id.prefix(1).uppercased() + id.dropFirst()
    let tabBarButton = app.tabBars.buttons[title].firstMatch
    // Right after launch the tab bar may not exist yet, while the hidden copy already does.
    if tabBarButton.waitForExistence(timeout: 5) {
        return tabBarButton
    }
    // Scrolling down minimizes the tab bar to the current tab; scrolling back up restores it.
    for _ in 0..<3 where !tabBarButton.exists {
        app.swipeDown()
    }
    if tabBarButton.waitForExistence(timeout: 3) {
        return tabBarButton
    }
    let candidates = app.buttons.matching(identifier: title).allElementsBoundByIndex
    return candidates.first { !$0.frame.isEmpty && $0.frame.minX.isFinite } ?? app.buttons[title].firstMatch
}

/// Submits the focused field so the keyboard, which covers the native tab bar, goes away.
@MainActor
func dismissKeyboardIfNeeded(in app: XCUIApplication) {
    guard app.keyboards.firstMatch.exists else { return }
    app.typeText("\n")
    _ = waitForElementToDisappear(app.keyboards.firstMatch, timeout: 3)
}

@MainActor
func tapOffRecordTab(_ id: String, in app: XCUIApplication) {
    let tab = offRecordTabButton(id, in: app).firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 8), "Missing tab \(id)")
    tab.tap()
}

@MainActor
func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
    for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
        app.swipeUp()
    }
}

/// Scrolls until `element` sits fully above the Record bar and tab bar. Their glass touch
/// areas reach slightly past what's drawn, so "hittable" alone can still tap the bar.
@MainActor
func scrollClearOfBottomBars(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
    for _ in 0..<maxSwipes {
        if element.exists, element.isHittable, element.frame.maxY < bottomBarsMinY(in: app) - 16 {
            return
        }
        app.swipeUp()
    }
}

/// Top edge of the lowest on-screen chrome: the Record bar or the tab bar.
@MainActor
func bottomBarsMinY(in app: XCUIApplication) -> CGFloat {
    let bars = [app.tabBars.firstMatch, app.descendants(matching: .any)["todayDock.record"].firstMatch]
    return bars.filter(\.exists).map(\.frame.minY).min() ?? app.frame.maxY
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
