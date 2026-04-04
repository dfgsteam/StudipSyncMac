//
//  StudipSyncUITests.swift
//  StudipSyncUITests
//
//  Created by Julius Hunold on 2026-04-01.
//

import XCTest

final class StudipSyncUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMainWindowSmoke() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        app.typeKey(",", modifierFlags: .command)

        let cacheButton = app.buttons["Cache leeren"]
        XCTAssertTrue(cacheButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Base-URL speichern"].exists)
    }
}
