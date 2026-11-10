import XCTest

final class HubEarlierPhotosTests: XCTestCase {
  @MainActor private func launch(_ scenario: String, appearance: String = "light") -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "app.backupduck.catalog")
    app.launchArguments = ["-scenario", scenario, "-appearance", appearance,
      "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    return app
  }

  @MainActor private func card(_ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "hub.earlier_summary").firstMatch
  }

  @MainActor private func record(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }

  @MainActor func testCompletedEarlierPhotosHasNoProgressOrHiddenRecordShortcut() throws {
    for appearance in ["light", "dark"] {
      let app = launch("hub.history-saved", appearance: appearance)
      let earlier = card(app)
      XCTAssertTrue(earlier.waitForExistence(timeout: 15))
      XCTAssertTrue(app.staticTexts["All earlier photos are in the backup"].exists)
      XCTAssertEqual(earlier.progressIndicators.count, 0)
      let overall = app.staticTexts["All your photos are in the Pixel’s Photos"]
      let recent = app.staticTexts["Recently Backed Up"]
      XCTAssertTrue(overall.exists); XCTAssertTrue(recent.exists)
      XCTAssertLessThan(overall.frame.maxY, earlier.frame.minY)
      XCTAssertLessThan(earlier.frame.maxY, recent.frame.minY)
      record(app, "earlier-completed-" + appearance)
      earlier.tap()
      XCTAssertFalse(app.navigationBars["Backup History"].waitForExistence(timeout: 1))
      XCTAssertTrue(earlier.exists, "The status card is not an implicit saved-record shortcut")
      let records = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Backup History")).firstMatch
      for _ in 0..<3 where !records.isHittable { app.swipeUp() }
      XCTAssertTrue(records.isHittable); records.tap()
      XCTAssertTrue(app.navigationBars["Backup History"].waitForExistence(timeout: 5))
    }
  }

  @MainActor func testIncompletePublicationKeepsRealProgress() {
    let app = launch("hub.history-saving")
    let earlier = card(app)
    XCTAssertTrue(earlier.waitForExistence(timeout: 15))
    XCTAssertTrue(earlier.progressIndicators.firstMatch.exists)
    XCTAssertFalse(app.staticTexts["All earlier photos are in the backup"].exists)
    record(app, "earlier-still-saving")
  }

  @MainActor func testPausedEarlierPhotosKeepsItsExplicitResumeControl() {
    let app = launch("hub.earlier-paused")
    let earlier = card(app)
    XCTAssertTrue(earlier.waitForExistence(timeout: 15))
    XCTAssertTrue(earlier.buttons["Resume"].isHittable)
    XCTAssertEqual(earlier.progressIndicators.count, 0)
    record(app, "earlier-paused-resume")
  }
}
