import XCTest

final class SelectedViewerToolbarTests: XCTestCase {
  @MainActor func testCenteredBackupActionLeavesThePhotoSelectionIndependentlyTouchable() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "app.backupduck.catalog")
    app.launchArguments = ["-scenario", "selection.review.open", "-appearance", "light",
      "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let browse = app.buttons["calendar.selected_browse"]
    XCTAssertTrue(browse.waitForExistence(timeout: 15))
    XCTAssertTrue(browse.isHittable)
    browse.tap()
    let backup = app.buttons["calendar.selected_preview_backup"]
    let check = app.buttons["calendar.selected_preview_toggle"]
    XCTAssertTrue(backup.waitForExistence(timeout: 10))
    XCTAssertTrue(check.waitForExistence(timeout: 10))
    XCTAssertTrue(backup.isHittable); XCTAssertTrue(check.isHittable)
    XCTAssertTrue(backup.label.contains("12"), backup.label)
    XCTAssertEqual(backup.frame.midX, app.frame.midX, accuracy: 2)
    XCTAssertEqual(check.frame.width, 44, accuracy: 1)
    XCTAssertEqual(check.frame.height, 44, accuracy: 1)
    XCTAssertFalse(backup.frame.intersects(check.frame))
    let frameRecord = "backup=\(backup.frame), photoCheck=\(check.frame), app=\(app.frame)"
    let frames = XCTAttachment(string: frameRecord); frames.name = "actual-native-toolbar-and-photo-check-frames"; frames.lifetime = .keepAlways; add(frames)
    let before = XCTAttachment(screenshot: app.screenshot()); before.name = "selected-detail-before-check-touch"; before.lifetime = .keepAlways; add(before)
    XCTAssertTrue(check.isSelected)
    check.tap()
    let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      backup.label.contains("11") && !check.isSelected
    }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    XCTAssertTrue(backup.isHittable)
    XCTAssertEqual(backup.frame.midX, app.frame.midX, accuracy: 2)
    let filmstrip = app.collectionViews["library.preview.filmstrip"]
    XCTAssertTrue(filmstrip.waitForExistence(timeout: 5))
    XCTAssertGreaterThan(filmstrip.cells.count, 0, "The virtualized filmstrip remains browsable")
    let after = XCTAttachment(screenshot: app.screenshot()); after.name = "selected-detail-after-check-touch"; after.lifetime = .keepAlways; add(after)
    let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "selected-detail-after-touch-accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    let back = app.navigationBars.buttons["BackButton"].firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
    let review = app.collectionViews["calendar.selected_grid"]
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    XCTAssertEqual(review.cells.count, 12, "The review retains all twelve batch members after deselecting the current photo")
    let returned = XCTAttachment(screenshot: app.screenshot()); returned.name = "selected-review-retains-twelve-after-touch"; returned.lifetime = .keepAlways; add(returned)
    print("SELECTED_TOOLBAR_NATIVE_FRAMES \(frameRecord)")
  }
}
