import XCTest

@MainActor final class JourneyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testKeyboardDismissalAndBlockingLoad() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-test-reset", "--ui-test-loading"]
        app.launch()
        let input = app.textFields["registrationInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("DEMO")
        let close = app.buttons["closeKeyboard"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.tabBars.buttons["Historikk"].isHittable)
        let onboarding = XCTAttachment(screenshot: app.screenshot())
        onboarding.name = "Centered onboarding"; onboarding.lifetime = .keepAlways; add(onboarding)
        app.buttons["findCar"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["loadingSpinner"].waitForExistence(timeout: 3))
        let loading = XCTAttachment(screenshot: app.screenshot())
        loading.name = "Centered loading"; loading.lifetime = .keepAlways; add(loading)
        let mileage = app.textFields["mileageInput"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 20))
        mileage.tap(); mileage.typeText("4000000")
        close.tap()
        app.buttons["addCar"].tap()
        XCTAssertTrue(app.staticTexts["Skriv inn kilometerstanden."].waitForExistence(timeout: 3))
        XCTAssertTrue(mileage.exists)
        XCTAssertFalse(app.descendants(matching: .any)["loadingSpinner"].exists)
    }

    func testSelectionPartialSwipeAcceptanceAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-test-reset"]
        app.launch()
        let input = app.textFields["registrationInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("DEMO")
        app.buttons["findCar"].tap()
        let mileage = app.textFields["mileageInput"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 5))
        mileage.tap(); mileage.typeText("124239")
        let closeKeyboard = app.buttons["closeKeyboard"]
        XCTAssertTrue(closeKeyboard.waitForExistence(timeout: 3))
        closeKeyboard.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["addCar"].tap()
        let arrange = app.buttons["arrangeNextService"]
        XCTAssertTrue(arrange.waitForExistence(timeout: 5))
        if !arrange.isHittable { app.swipeUp() }
        arrange.tap()
        let second = app.buttons["option2"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        if !second.isHittable { app.swipeUp() }
        second.tap()
        app.buttons["showSelectedOffer"].tap()
        XCTAssertTrue(app.buttons["createTimedOffer"].waitForExistence(timeout: 5))
        app.buttons["createTimedOffer"].tap()
        let slider = app.buttons["acceptSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demoverksted Sentrum"].exists)
        let vipps = app.buttons["payment-vipps"]
        if !vipps.isHittable { app.swipeUp() }
        vipps.tap()
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        let partial = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: partial)
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(app.buttons["backToCar"].exists)
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["backToCar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demoverksted Sentrum"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["viewHistory"].tap()
        let booking = app.buttons["history-eu_kontroll"]
        XCTAssertTrue(booking.waitForExistence(timeout: 5))
        booking.tap()
        XCTAssertTrue(app.buttons["rescheduleBooking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Vipps"].exists)
        app.buttons["rescheduleBooking"].tap()
        XCTAssertTrue(app.buttons["Lagre"].waitForExistence(timeout: 5))
        app.buttons["Lagre"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["Historikk"].tap()
        XCTAssertTrue(booking.waitForExistence(timeout: 5))
        booking.tap()
        let complete = app.buttons["completeBooking"]
        if !complete.isHittable { app.swipeUp() }
        complete.tap()
        app.buttons["Ferdig"].tap()
        app.segmentedControls.buttons["Fullførte"].tap()
        XCTAssertTrue(booking.waitForExistence(timeout: 5))
    }
}
