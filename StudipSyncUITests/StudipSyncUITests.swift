//
//  StudipSyncUITests.swift
//  StudipSyncUITests
//
//  Created by Julius Hunold on 2026-04-01.
//

import XCTest

final class StudipSyncUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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

        openSettingsWindow(using: app)
        let cacheButton = app.buttons["Cache leeren"]
        XCTAssertTrue(cacheButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Base-URL speichern"].exists)
    }

    @MainActor
    func testManualSyncUpdatesVisibleStatus() throws {
        let app = XCUIApplication()
        app.launch()

        let syncButton = app.buttons["toolbar.syncNow"]
        XCTAssertTrue(syncButton.waitForExistence(timeout: 5))

        let statusLabel = app.staticTexts["sidebar.syncStatus"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5))

        syncButton.click()

        let predicate = NSPredicate(format: "label != %@", "Idle")
        expectation(for: predicate, evaluatedWith: statusLabel)
        waitForExpectations(timeout: 10)

        let current = statusLabel.label.lowercased()
        XCTAssertTrue(
            current.contains("synchronizing")
                || current.contains("last successful sync")
                || current.contains("error:")
                || current.contains("offline")
                || current.contains("running")
        )
    }

    @MainActor
    private func openSettingsWindow(using app: XCUIApplication) {
        let appMenuBarItem = app.menuBars.menuBarItems.element(boundBy: 0)
        XCTAssertTrue(appMenuBarItem.waitForExistence(timeout: 5))
        appMenuBarItem.click()

        let settingsPredicate = NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Einst", "Settings")
        let settingsItem = appMenuBarItem.menus.menuItems.matching(settingsPredicate).firstMatch
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 5))
        settingsItem.click()
    }
}
