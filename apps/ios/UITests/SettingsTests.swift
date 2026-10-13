import XCTest

final class SettingsTests: XCTestCase {
  /// Only used on isolated acceptance simulators. Existing delayed Photos
  /// permission alerts can remain after a previous test app terminates.
  @MainActor private func launchIsolated(_ app: XCUIApplication) {
    app.launch()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@",
      ["Allow Full Access", "允许完全访问"])).firstMatch
    if allow.waitForExistence(timeout: 2) { allow.tap() }
  }

  /// TabView moves its native navigation to the top on iPadOS 18+.
  /// Match the actual controls on either platform rather than requiring TabBar.
  @MainActor private func navigation(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
    let bottom = app.tabBars.buttons.element(boundBy: index)
    if bottom.exists { return bottom }
    let symbols = ["photo.on.rectangle", "arrow.triangle.2.circlepath", "externaldrive.badge.wifi", "gearshape"]
    return app.buttons.matching(identifier: symbols[index]).firstMatch
  }

  @MainActor private func openAllTransfers(_ app: XCUIApplication) {
    XCTAssertTrue(navigation(app, 1).waitForExistence(timeout: 20)); navigation(app, 1).tap()
    let matches = app.buttons.matching(identifier: "backup.all_tasks")
    for _ in 0..<8 { if matches.allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }; app.swipeUp() }
    guard let all = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
      recordWindow(app, "All transfers unavailable — count \(matches.count)")
      XCTFail("No visible All transfers action. Inspect the actual Backup window/fixture; do not substitute a different route.")
      return
    }
    all.tap()
    XCTAssertTrue(app.buttons["transfers.sort"].waitForExistence(timeout: 10))
  }

  @MainActor private func recordWindow(_ app: XCUIApplication, _ name: String) {
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = name + " — accessibility hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = name + " — actual window"; screen.lifetime = .keepAlways; add(screen)
    print(name + "\n" + app.debugDescription)
  }

  @MainActor private func chooseTransferCategory(_ app: XCUIApplication, _ label: String) {
    let picker = app.descendants(matching: .any)["transfers.common_filter"].firstMatch
    XCTAssertTrue(picker.waitForExistence(timeout: 10))
    let choice = picker.buttons[label]
    XCTAssertTrue(choice.isHittable); choice.tap()
    XCTAssertTrue(choice.isSelected)
  }

  @MainActor private func chooseTransferSort(_ app: XCUIApplication, _ id: String, label: String) {
    app.buttons["transfers.sort"].tap()
    let choice = app.buttons["transfers.sort_" + id]
    XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
    XCTAssertTrue(app.buttons["transfers.sort"].label.contains(label))
  }

  @MainActor func testMediaPreviewNavigationAndInformation() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    app.buttons["library.filter"].tap(); app.buttons["Photos"].tap()
    let grid = app.collectionViews["library.grid"]
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in grid.cells.count >= 2 }, object: grid)
    guard grid.waitForExistence(timeout: 10), XCTWaiter.wait(for: [ready], timeout: 8) == .completed else {
      throw XCTSkip("Requires an isolated simulator with at least two synthetic photos")
    }
    try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable }).tap()
    recordWindow(app, "After preview tap")
    guard app.buttons["library.preview.close"].waitForExistence(timeout: 5) else {
      XCTFail("Preview did not open"); return
    }
    let photo = app.images["library.preview.photo"]
    XCTAssertTrue(photo.waitForExistence(timeout: 10))
    photo.doubleTap()
    app.buttons["library.preview.info"].tap()
    XCTAssertTrue(app.staticTexts["preview.info.dimensions"].waitForExistence(timeout: 5))
    recordWindow(app, "Preview information")
    app.buttons["preview.info.close"].tap()
    photo.swipeLeft()
    XCTAssertTrue(photo.waitForExistence(timeout: 10))
    photo.swipeRight()
    XCTAssertTrue(photo.waitForExistence(timeout: 10))
    recordWindow(app, "High quality photo preview")
    app.buttons["library.preview.close"].tap()
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
  }

  @MainActor func testBackupScopeConfigurationPersists() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    navigation(app, 1).tap()
    let more = app.buttons["backup.manage_source"]
    for _ in 0..<5 { if more.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(more.isHittable); more.tap()
    let types = app.buttons["backup.scope.types"]
    for _ in 0..<6 { if types.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(types.isHittable); types.tap()
    let photo = app.buttons["backup.scope.type.photo"]
    XCTAssertTrue(photo.waitForExistence(timeout: 5)); if photo.isSelected { photo.tap() }
    XCTAssertFalse(photo.isSelected)
    recordWindow(app, "Media type editor — library vocabulary")
    app.buttons["page.header.back"].tap()
    app.buttons["backup.scope.albums"].tap()
    let search = app.textFields["backup.scope.album_search"]
    XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Scope fixture A")
    let album = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Scope fixture A")).firstMatch
    XCTAssertTrue(album.waitForExistence(timeout: 5)); album.tap()
    recordWindow(app, "Searchable album editor — separate destination")
    app.terminate(); launchIsolated(app)
    navigation(app, 1).tap()
    for _ in 0..<5 { if more.isHittable { break }; app.swipeUp() }; more.tap()
    for _ in 0..<6 { if types.isHittable { break }; app.swipeUp() }; types.tap()
    XCTAssertFalse(photo.isSelected); photo.tap()
    app.buttons["page.header.back"].tap(); app.buttons["backup.scope.albums"].tap()
    app.buttons["backup.scope.all_albums"].tap()
    XCTAssertTrue(app.buttons["backup.scope.all_albums"].isSelected)
  }

  @MainActor func testCloudConsentUsesSharedSheetAndCanDecline() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--preview-consent-fixture"]
    launchIsolated(app)
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable }).tap()
    let allow = app.buttons["preview.cloud.allow"]
    XCTAssertTrue(allow.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["preview.cloud.decline"].isHittable)
    XCTAssertFalse(app.alerts.firstMatch.exists)
    let originalButtonY = allow.frame.minY
    let title = app.staticTexts["Load previews from iCloud"]
    XCTAssertTrue(title.exists)
    title.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.5)).press(forDuration: 0.05,
      thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.15)),withVelocity: .slow,thenHoldForDuration: 0.1)
    XCTAssertEqual(allow.frame.minY,originalButtonY,accuracy: 8,"A short confirmation has no expandable empty detent")
    recordWindow(app,"Application cloud consent — shared sheet contract")
    app.buttons["preview.cloud.decline"].tap()
    XCTAssertTrue(app.buttons["library.preview.close"].waitForExistence(timeout: 5))
    app.buttons["library.preview.close"].tap()
  }

  @MainActor func testMidLibraryPinchKeepsTouchedPhotoInPlace() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    let total = Int(app.staticTexts["library.count"].label.filter(\.isNumber)) ?? 0
    XCTAssertGreaterThan(total, 80, "Import the isolated long-library fixture before testing an interior anchor")
    grid.swipeDown(); grid.swipeDown()
    let middle = try XCTUnwrap(grid.cells.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.midY > 280 && $0.frame.midY < 550 && $0.frame.midX > 130 && $0.frame.midX < 300 }.first)
    let id = middle.identifier, y = middle.frame.midY, width = middle.frame.width
    middle.pinch(withScale: 0.65, velocity: -0.6)
    // A CADisplayLink transition does not participate in XCTest's idle tracking.
    // Observe the real settled density before comparing accessibility geometry.
    let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "5 columns"), object: grid)
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    let changed = grid.cells[id]
    XCTAssertTrue(changed.isHittable)
    XCTAssertLessThan(changed.frame.width,width)
    XCTAssertEqual(changed.frame.midY,y,accuracy: 35,"The touched photo must retain its vertical context inside a long library")
    recordWindow(app,"Mid-library pinch — same asset under the fingers")
    changed.pinch(withScale: 1.5,velocity: 0.6)
    let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "3 columns"), object: grid)
    XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
    XCTAssertTrue(grid.cells[id].isHittable)
    recordWindow(app,"Mid-library expansion — stable identity and continuous layout")
  }

  @MainActor func testCalendarControlsRemainTappableAfterNativeTransition() throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("Native tab minimization requires iOS 26") }
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    grid.swipeDown()
    let years = app.buttons["Years"]
    XCTAssertTrue(years.waitForExistence(timeout: 5))
    let disappears = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !years.isHittable }, object: years)
    disappears.isInverted = true
    XCTAssertEqual(XCTWaiter.wait(for: [disappears], timeout: 3), .completed, "Calendar actions must survive the settled native transition")
    years.tap()
    app.buttons["Months"].tap()
    app.buttons["All"].tap()
    XCTAssertTrue(app.buttons["Years"].isHittable)
    app.buttons["library.select_mode"].tap()
    let review = app.buttons["calendar.review_selected"]
    XCTAssertEqual(review.label, "Select Items")
    XCTAssertFalse(review.isEnabled)
    XCTAssertLessThan(review.frame.width, grid.frame.width * 0.75)
    let upload = app.buttons["calendar.backup_selected"]
    XCTAssertTrue(upload.exists)
    XCTAssertLessThan(upload.frame.midY, 220, "Backup belongs beside the filter in the native header")
    let photo = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable && $0.frame.midY > 260 && $0.frame.midY < 600 })
    photo.tap()
    XCTAssertTrue(review.isEnabled)
    XCTAssertTrue(review.label.contains("1"))
    XCTAssertLessThan(review.frame.width, grid.frame.width * 0.85)
    recordWindow(app, "Compact selected review with top backup action")
  }

  @MainActor func testLibraryNativeChromeAndSelectionGroups() throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("Native tab morphing requires iOS 26") }
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    XCTAssertTrue(app.tabBars.buttons["Backup"].isHittable)
    XCTAssertFalse(app.buttons["Years"].isHittable)
    recordWindow(app,"Native Library controls — full navigation")
    grid.swipeDown()
    XCTAssertTrue(app.buttons["Years"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Years"].isHittable)
    XCTAssertFalse(app.tabBars.buttons["Backup"].isHittable)
    recordWindow(app,"Native Library controls — minimized tab and inline calendar")
    app.buttons["Library"].tap()
    XCTAssertTrue(app.tabBars.buttons["Backup"].isHittable)
    XCTAssertFalse(app.buttons["Years"].isHittable)
    app.buttons["library.select_mode"].tap()
    XCTAssertTrue(app.buttons["library.filter"].isHittable)
    XCTAssertEqual(app.buttons["library.select_mode"].label, "Done")
    let photo = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable && $0.frame.midY > 260 && $0.frame.midY < 600 })
    photo.tap()
    XCTAssertTrue(app.buttons["calendar.review_selected"].isHittable)
    XCTAssertTrue(app.buttons["calendar.review_selected"].label.contains("1"))
    recordWindow(app,"Native selection — existing filter, close, readable count")
    app.buttons["library.select_mode"].tap()
    XCTAssertTrue(app.tabBars.buttons["Backup"].isHittable)
    recordWindow(app,"Native selection exits — restored navigation")
  }

  @MainActor func testCalendarGridHierarchyAndSelectedReview() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    let grid=app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout:10))
    grid.swipeDown()
    XCTAssertTrue(app.buttons["Years"].waitForExistence(timeout:5));app.buttons["Years"].tap()
    let year = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable })
    recordWindow(app,"iPhone calendar — year covers")
    year.tap()
    XCTAssertTrue(app.buttons["Months"].isSelected)
    recordWindow(app,"iPhone calendar — month day mosaic")
    let day = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable })
    let id=day.identifier;day.tap()
    XCTAssertTrue(grid.cells[id].waitForExistence(timeout:5))
    XCTAssertTrue(grid.cells[id].isHittable,"Drill-down retains the chosen day cover as the All-grid destination")
    recordWindow(app,"iPhone calendar — All at the chosen day")
    app.buttons["library.select_mode"].tap()
    let cell=try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable });cell.tap()
    XCTAssertTrue(app.buttons["calendar.review_selected"].label.contains("1"))
    app.buttons["calendar.review_selected"].tap()
    let review=app.collectionViews["calendar.selected_grid"]
    XCTAssertTrue(review.waitForExistence(timeout:5));XCTAssertEqual(review.cells.count,1)
    recordWindow(app,"iPhone calendar — selected items only")
    app.buttons["Deselect All"].tap()
    XCTAssertTrue(app.navigationBars.staticTexts.containing(NSPredicate(format:"label CONTAINS '0'")).firstMatch.exists)
    app.navigationBars.buttons.element(boundBy:0).tap()
    XCTAssertEqual(app.buttons["calendar.review_selected"].label, "Select Items")
  }

  @MainActor func testCalendarDisplayOptionsDarkAndLargeText() throws {
    continueAfterFailure=false
    let app=XCUIApplication()
    app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US","-duckAppearance","dark",
      "-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXL"]
    launchIsolated(app)
    let grid=app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout:10))
    app.buttons["library.filter"].tap();app.buttons["Display Options"].tap();app.buttons["Zoom Out"].tap()
    XCTAssertTrue(app.buttons["library.select_mode"].isHittable)
    recordWindow(app,"iPhone calendar — dark larger type and zoom menu")
    app.buttons["library.filter"].tap();app.buttons["Display Options"].tap();app.buttons["Original Aspect Grid"].tap()
    recordWindow(app,"iPhone calendar — original aspect thumbnails")
    grid.swipeDown()
    XCTAssertTrue(app.buttons["Years"].waitForExistence(timeout:5));app.buttons["Years"].tap()
    recordWindow(app,"iPhone calendar — year covers in dark appearance")
  }

  @MainActor func testMediaPreviewLargeTextConsentAndInformation() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--preview-consent-fixture"]
    launchIsolated(app)
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable }).tap()
    XCTAssertTrue(app.buttons["preview.cloud.allow"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["preview.cloud.decline"].isHittable)
    recordWindow(app,"Preview consent — Chinese accessibility text")
    app.buttons["preview.cloud.decline"].tap()
    XCTAssertTrue(app.buttons["library.preview.info"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["library.preview.close"].isHittable)
    recordWindow(app,"Preview header — Chinese accessibility text")
    app.buttons["library.preview.info"].tap()
    XCTAssertTrue(app.buttons["preview.info.close"].waitForExistence(timeout: 5))
    app.buttons["preview.info.close"].tap(); app.buttons["library.preview.close"].tap()
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
  }

  @MainActor func testNativeViewerScrubbingAndChangedAssetReturn() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    app.buttons["library.filter"].tap(); app.buttons["Photos"].tap()
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    let first = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable }); first.tap()
    let images = app.images.matching(identifier: "library.preview.photo")
    XCTAssertTrue(app.buttons["library.preview.close"].waitForExistence(timeout: 5))
    let photo = try XCTUnwrap(images.allElementsBoundByIndex.first { $0.isHittable })
    let initial = photo.value as? String
    let pager = app.scrollViews["library.preview.pager"]
    let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85,dy: 0.45))
    start.press(forDuration: 0.05,thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.08,dy: 0.45)),withVelocity: .slow,thenHoldForDuration: 0.15)
    let next = try XCTUnwrap(images.allElementsBoundByIndex.first { $0.isHittable }?.value as? String)
    XCTAssertNotEqual(next,initial)
    pager.coordinate(withNormalizedOffset: CGVector(dx: 0.55,dy: 0.45)).press(forDuration: 0.05,thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.49,dy: 0.45)),withVelocity: .slow,thenHoldForDuration: 0.2)
    XCTAssertEqual(images.allElementsBoundByIndex.first { $0.isHittable }?.value as? String,next)
    let strip = app.collectionViews["library.preview.filmstrip"]
    XCTAssertTrue(strip.exists)
    strip.coordinate(withNormalizedOffset: CGVector(dx: 0.8,dy: 0.5)).press(forDuration: 0.05,thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: 0.25,dy: 0.5)),withVelocity: .slow,thenHoldForDuration: 0.2)
    let scrubbed = try XCTUnwrap(images.allElementsBoundByIndex.first { $0.isHittable }?.value as? String)
    XCTAssertNotEqual(scrubbed,next)
    recordWindow(app,"Native filmstrip after scrubbing")
    app.buttons["library.preview.info"].tap()
    XCTAssertTrue(app.staticTexts["preview.info.dimensions"].waitForExistence(timeout: 5))
    app.buttons["preview.info.close"].tap()
    pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.3)).press(forDuration: 0.05,thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.85)),withVelocity: .slow,thenHoldForDuration: 0.1)
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    XCTAssertTrue(grid.cells["library.asset."+scrubbed].isHittable,"Return destination is the current asset rather than the opening asset")
    recordWindow(app,"Return to changed current asset")
  }

  @MainActor func testContinuousPagingDrawerAndDismissal() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    app.buttons["library.filter"].tap(); app.buttons["Photos"].tap()
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    let first = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable })
    let initialID = first.identifier; first.tap()
    let images = app.images.matching(identifier: "library.preview.photo")
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in images.allElementsBoundByIndex.contains { $0.isHittable } }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 10),.completed)
    let image = try XCTUnwrap(images.allElementsBoundByIndex.first { $0.isHittable })
    XCTAssertTrue(image.waitForExistence(timeout: 10))
    let initial = image.value as? String
    let from = image.coordinate(withNormalizedOffset: CGVector(dx: 0.85,dy: 0.5))
    let to = image.coordinate(withNormalizedOffset: CGVector(dx: 0.05,dy: 0.5))
    from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertTrue(app.buttons["library.preview.close"].waitForExistence(timeout: 5))
    XCTAssertNotEqual(images.allElementsBoundByIndex.first { $0.isHittable }?.value as? String, initial)
    recordWindow(app, "Native continuous page after held drag")
    let current = try XCTUnwrap(images.allElementsBoundByIndex.first { $0.isHittable })
    current.doubleTap(); current.doubleTap()
    current.swipeUp()
    XCTAssertTrue(app.staticTexts["preview.info.dimensions"].waitForExistence(timeout: 5))
    XCTAssertTrue(images.allElementsBoundByIndex.contains { $0.isHittable }, "Information keeps the photo in the viewport")
    recordWindow(app, "Information drawer — photo remains visible")
    app.buttons["preview.info.close"].tap()
    try XCTUnwrap(images.allElementsBoundByIndex.first { $0.isHittable }).swipeDown()
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: grid.cells[initialID])
    XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
  }

  @MainActor func testTimelineViewsAndPinchPreservePhotoContext() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    let grid = app.collectionViews["library.grid"]
    guard grid.waitForExistence(timeout: 10), grid.cells.count >= 2 else {
      throw XCTSkip("Requires the isolated synthetic photo library")
    }
    grid.swipeDown()
    app.buttons["Months"].tap()
    XCTAssertTrue(app.staticTexts["calendar.date_badge"].firstMatch.waitForExistence(timeout:5))
    let day=try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable })
    let id=day.identifier;day.tap()
    XCTAssertTrue(grid.cells[id].isHittable)
    let interior=try XCTUnwrap(grid.cells.allElementsBoundByIndex.first {
      $0.isHittable && $0.frame.midY>280 && $0.frame.midY<550
    })
    let focusedID=interior.identifier,width=interior.frame.width
    interior.pinch(withScale:0.65,velocity:-0.6)
    XCTAssertTrue(grid.cells[focusedID].isHittable)
    XCTAssertLessThan(grid.cells[focusedID].frame.width,width)
    recordWindow(app,"Calendar drill-down and independent All-grid density")
    grid.cells[focusedID].tap()
    XCTAssertTrue(app.buttons["library.preview.close"].waitForExistence(timeout:10))
    app.buttons["library.preview.close"].tap()
    XCTAssertTrue(grid.cells[focusedID].isHittable)
  }

  @MainActor func testNativeVideoPreviewAndLargeDarkLibrary() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "dark",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    launchIsolated(app)
    let filter = app.buttons["library.filter"]
    XCTAssertTrue(filter.waitForExistence(timeout: 10)); filter.tap(); app.buttons["Videos"].tap()
    let grid = app.collectionViews["library.grid"]
    guard grid.waitForExistence(timeout: 10), grid.cells.count > 0 else {
      throw XCTSkip("Requires a synthetic local video in the isolated simulator")
    }
    recordWindow(app, "Large dark gallery and navigation")
    try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable }).tap()
    XCTAssertTrue(app.descendants(matching: .any)["library.preview.video"].firstMatch.waitForExistence(timeout: 10))
    recordWindow(app, "Native local video preview")
    app.buttons["library.preview.info"].tap()
    recordWindow(app, "Native video information")
    app.buttons["Done"].firstMatch.tap(); app.buttons["library.preview.close"].tap()
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
  }

  @MainActor func testDesignReviewScreens() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 1).waitForExistence(timeout: 20))
    for (index, name) in [(1, "backup"), (2, "receiver"), (3, "settings"), (0, "library")] {
      navigation(app, index).tap()
      Thread.sleep(forTimeInterval: 1) // Capture after the system tab transition finishes.
      let screen = XCTAttachment(screenshot: app.screenshot())
      screen.name = "design-review-" + name; screen.lifetime = .keepAlways; add(screen)
    }
    navigation(app, 1).tap()
    let all = app.buttons["全部传输任务"].firstMatch
    if all.exists && all.isHittable {
      all.tap()
      XCTAssertTrue(app.staticTexts["transfers.title"].waitForExistence(timeout: 10))
      Thread.sleep(forTimeInterval: 1)
      let screen = XCTAttachment(screenshot: app.screenshot())
      screen.name = "design-review-transfers"; screen.lifetime = .keepAlways; add(screen)
    }
  }

  @MainActor func testCompactStatusIndicatorsOpenDetails() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    XCTAssertTrue(navigation(app, 1).waitForExistence(timeout: 20))
    navigation(app, 1).tap()
    let backup = app.buttons["backup.status_indicator"]
    XCTAssertTrue(backup.waitForExistence(timeout: 10))
    XCTAssertLessThanOrEqual(backup.frame.height, 48)
    backup.tap()
    let detail = XCTAttachment(screenshot: app.screenshot())
    detail.name = "design-review-status-detail"; detail.lifetime = .keepAlways; add(detail)
    print("Isolated status detail: " + app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
    app.buttons["Done"].tap()
    navigation(app, 2).tap()
    let receiver = app.buttons["receiver.status_indicator"]
    XCTAssertTrue(receiver.waitForExistence(timeout: 10))
    XCTAssertLessThanOrEqual(receiver.frame.height, 48)
    receiver.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
    app.buttons["Done"].tap()
  }

  @MainActor func testTaskExplanationsAndTrailingFilter() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app); openAllTransfers(app)
    let picker = app.descendants(matching: .any)["transfers.common_filter"].firstMatch
    XCTAssertEqual(picker.buttons.count, 4, "Ordinary tasks expose exactly four categories")
    for label in ["All", "Active", "Attention", "Saved"] { chooseTransferCategory(app, label) }
    XCTAssertFalse(app.buttons["Queued"].exists)
    XCTAssertFalse(app.buttons["Sent to phone"].exists)
    let guide = app.buttons["transfers.guide"]
    XCTAssertTrue(guide.isHittable); guide.tap()
    XCTAssertTrue(app.staticTexts["Originals are prepared, but sending has not started."].waitForExistence(timeout: 10))
    let receipt = app.staticTexts["A receipt is confirmed, but no gallery result is available; this remains active."]
    for _ in 0..<8 { if receipt.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(receipt.isHittable)
    let cloud = app.staticTexts["This does not confirm Google Photos cloud upload."]
    for _ in 0..<8 { if cloud.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(cloud.isHittable, "The standalone guide keeps gallery and cloud facts separate")
    let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Four task categories — independent state guide"
    screen.lifetime = .keepAlways; add(screen)
    app.buttons["Done"].firstMatch.tap()
    XCTAssertTrue(picker.waitForExistence(timeout: 10)); XCTAssertTrue(picker.buttons["Saved"].isSelected)
    XCTAssertFalse(receipt.exists, "Closing guidance returns to the same task filter")
    app.buttons["page.header.back"].tap()
  }

  @MainActor func testTransferSortPersistsAcrossListsAndRelaunch() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app); openAllTransfers(app)
    chooseTransferCategory(app, "All")
    chooseTransferSort(app, "capture_latest", label: "Latest capture")
    chooseTransferSort(app, "capture_earliest", label: "Earliest capture")
    chooseTransferCategory(app, "Saved")
    chooseTransferSort(app, "added_latest", label: "Recently added")
    chooseTransferSort(app, "added_earliest", label: "First added")
    chooseTransferCategory(app, "All")
    XCTAssertTrue(app.buttons["transfers.sort"].label.contains("Earliest capture"), "Each category retains its own ordering")
    app.terminate(); launchIsolated(app); openAllTransfers(app)
    chooseTransferCategory(app, "All")
    XCTAssertTrue(app.buttons["transfers.sort"].label.contains("Earliest capture"))
    chooseTransferCategory(app, "Saved")
    XCTAssertTrue(app.buttons["transfers.sort"].label.contains("First added"))
    let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Direct sort choices — category-specific persistence"
    screen.lifetime = .keepAlways; add(screen)
  }

  @MainActor func testBackupSettingsKeepPreparationInOrdinaryTaskFeed() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 1).waitForExistence(timeout: 20)); navigation(app, 1).tap()
    let entries = app.buttons.matching(identifier: "backup.manage_source")
    for _ in 0..<8 { if entries.allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }; app.swipeUp() }
    guard let manage = entries.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
      recordWindow(app, "Backup settings unavailable — count \(entries.count)")
      XCTFail("No visible source settings action. The isolated source fixture must be accessible through the genuine Backup page.")
      return
    }
    manage.tap()
    // Preparation belongs to Active/Attention. Scan progress stays with its
    // controls; settings must not add separate source-record navigation.
    for _ in 0..<6 {
      XCTAssertFalse(app.buttons["backup.preferences.preparing"].exists)
      XCTAssertFalse(app.buttons["backup.preferences.history"].exists)
      app.swipeUp()
    }
    recordWindow(app, "Backup settings — ordinary task feed owns preparation")
    app.buttons["page.header.back"].tap()
    openAllTransfers(app)
    for title in ["All", "Active", "Attention", "Saved"] {
      chooseTransferCategory(app, title)
    }
  }

  @MainActor func testAccessibleTextNavigationAndRotation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    defer { XCUIDevice.shared.orientation = .portrait }
    for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
      XCUIDevice.shared.orientation = orientation
      let settings = app.buttons["Settings"].firstMatch
      XCTAssertTrue(settings.waitForExistence(timeout: 20))
      for title in ["Library", "Backup", "Receiver", "Settings"] {
        let tab = app.buttons[title].firstMatch
        XCTAssertTrue(tab.isHittable, "Navigation must remain reachable at accessibility sizes")
        tab.tap()
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Accessible text — \(title) — \(orientation.rawValue)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
      }
      let help = app.buttons["settings.help"]
      for _ in 0..<12 {
        if help.exists && help.isHittable { break }
        app.swipeUp()
      }
      XCTAssertTrue(help.isHittable)
      help.tap()
      let body = app.staticTexts.matching(NSPredicate(
        format: "label BEGINSWITH %@", "Open Settings → Diagnostics → Activity log")).firstMatch
      for _ in 0..<25 {
        if body.exists && body.isHittable { break }
        app.swipeUp()
      }
      XCTAssertTrue(body.isHittable)
      let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screenshot.name = "Accessible help end — \(orientation.rawValue)"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      app.buttons["page.header.back"].tap()
    }
  }

  @MainActor func testHelpNavigationAndScrollingInBothLanguages() {
    continueAfterFailure = false
    for (language, title, finalSection, finalBody) in [
      ("en", "Using BackupDuck", "Collect useful diagnostics", "Open Settings → Diagnostics → Activity log"),
      ("zh-Hans", "使用与恢复", "提供排查信息", "在“设置 → 诊断 → 运行记录”中"),
    ] {
      let app = XCUIApplication()
      app.launchArguments = ["-AppleLanguages", "(\(language))"]
      app.launch()
      XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20))
      navigation(app, 3).tap()
      let help = app.buttons["settings.help"]
      for _ in 0..<8 {
        if help.exists && help.isHittable { break }
        app.swipeUp()
      }
      XCTAssertTrue(help.isHittable)
      help.tap()
      XCTAssertTrue(app.staticTexts["page.header.title"].waitForExistence(timeout: 10))
      XCTAssertEqual(app.staticTexts["page.header.title"].label, title)
      let end = app.staticTexts[finalSection]
      let body = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", finalBody)).firstMatch
      for _ in 0..<12 {
        if body.exists && body.isHittable && body.frame.maxY < (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY) { break }
        app.swipeUp()
      }
      XCTAssertTrue(end.isHittable, "The final help section must remain reachable")
      XCTAssertTrue(body.isHittable)
      XCTAssertLessThan(body.frame.maxY, app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY,
        "The last paragraph must scroll clear of the tab bar")
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = "Help end — \(language)"
      image.lifetime = .keepAlways
      add(image)
      app.buttons["page.header.back"].tap()
      XCTAssertTrue(app.buttons["settings.help"].waitForExistence(timeout: 5))
      app.terminate()
    }
  }

  @MainActor func testActivityLogOpensIndependentlyAndExports() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let settings = navigation(app, 3)
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    settings.tap()
    let log = app.buttons["settings.activity_log"]
    for _ in 0..<8 {
      if log.exists && log.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(log.isHittable)
    log.tap()
    let export = app.buttons["activity.export"]
    XCTAssertTrue(
      export.waitForExistence(timeout: 10),
      "Log entry must open its own sheet, not a storage picker")
    let enabled = NSPredicate(format: "enabled == true")
    expectation(for: enabled, evaluatedWith: export)
    waitForExpectations(timeout: 10)
    let details = app.buttons["activity.details"].firstMatch
    for _ in 0..<12 {
      if details.exists && details.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(details.exists && details.isHittable)
    let latest = app.buttons["activity.latest"]
    XCTAssertTrue(latest.isHittable)
    let latestPosition = latest.frame
    let firstPositionBeforeLatest = details.frame.minY
    latest.tap()
    XCTAssertTrue(latest.isHittable, "Show latest must not scroll away its own controls")
    XCTAssertEqual(latest.frame.minY, latestPosition.minY, accuracy: 2)
    XCTAssertEqual(details.frame.minY, firstPositionBeforeLatest, accuracy: 2, "First click must retain the gap below the Latest controls")
    let latestScreen = XCTAttachment(screenshot: app.screenshot())
    latestScreen.name = "Activity latest — stable controls and centered chevrons"
    latestScreen.lifetime = .keepAlways; add(latestScreen)
    let entryPosition = details.frame.minY
    details.tap()
    let detail = app.descendants(matching: .any)["activity.detail"].firstMatch
    XCTAssertTrue(detail.waitForExistence(timeout: 10), "One event opens an independent detail sheet")
    let detailDone = app.buttons["activity.detail.done"]
    if !detailDone.waitForExistence(timeout: 10) || !detailDone.isHittable {
      recordWindow(app, "Activity detail footer unavailable")
    }
    XCTAssertTrue(detailDone.isHittable)
    let detailScreen = XCTAttachment(screenshot: app.screenshot()); detailScreen.name = "Activity entry — independent detail sheet"
    detailScreen.lifetime = .keepAlways; add(detailScreen)
    detailDone.tap()
    XCTAssertTrue(details.waitForExistence(timeout: 10)); XCTAssertTrue(details.isHittable)
    XCTAssertEqual(details.frame.minY, entryPosition, accuracy: 3, "Returning from one event preserves the log list position")
    XCTAssertFalse(detail.exists)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Activity log with export action"
    screen.lifetime = .keepAlways
    add(screen)
    export.tap()
    let share = app.buttons["activity.export_share"]
    XCTAssertTrue(share.waitForExistence(timeout: 10), "Export must prepare a fresh report in the current window before sharing")
    XCTAssertFalse(app.otherElements["ActivityListView"].exists, "Preparing a file must not claim the system share operation completed")
    let prepared = XCTAttachment(screenshot: app.screenshot())
    prepared.name = "Diagnostic report — ready in current export sheet"; prepared.lifetime = .keepAlways; add(prepared)
    share.tap()
    XCTAssertTrue(
      app.otherElements["ActivityListView"].waitForExistence(timeout: 10),
      "The explicit Share action must present the native sharing sheet")
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "BackupDuck-diagnostics")
      ).firstMatch.exists, "The shared item must be the diagnostic file")
    let shared = XCTAttachment(screenshot: app.screenshot())
    shared.name = "Diagnostic file sharing sheet"
    shared.lifetime = .keepAlways
    add(shared)
  }
  @MainActor func testMainNavigationAndCacheIsolation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20))
    XCTAssertTrue((0..<4).allSatisfy { navigation(app, $0).exists })
    for (index, title) in ["Library", "Backup", "Receiver", "Settings"].enumerated() {
      navigation(app, index).tap()
      let screen = XCTAttachment(screenshot: app.screenshot())
      screen.name = title
      screen.lifetime = .keepAlways
      add(screen)
    }
    XCTAssertFalse(app.buttons["settings.cache_budget"].exists)
    app.buttons["settings.cache"].tap()
    XCTAssertTrue(app.buttons["settings.cache_budget"].waitForExistence(timeout: 10))
    XCTAssertFalse(
      app.buttons["settings.activity_log"].exists,
      "Cache controls must not contain the unrelated log action")
    navigation(app, 2).tap()
    XCTAssertTrue(app.buttons["receiver.scan"].waitForExistence(timeout: 10))
    navigation(app, 1).tap()
    app.buttons["backup.all_tasks"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["transfers.common_filter"].firstMatch.exists)
  }

  @MainActor func testPairingCameraFailureRemainsInWorkflow() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "system"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 2).waitForExistence(timeout: 20))
    navigation(app, 2).tap()
    app.buttons["receiver.scan"].tap()
    let failure = app.descendants(matching: .any)["pairing.camera_error"].firstMatch
    XCTAssertTrue(failure.waitForExistence(timeout: 15), "A simulator without a camera must give a visible recovery state")
    XCTAssertTrue(app.staticTexts["Scan the Pixel pairing code"].exists)
    XCTAssertTrue(app.buttons["pairing.retry"].isHittable)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Pairing — unavailable camera — recovery in current sheet"
    screen.lifetime = .keepAlways; add(screen)
    app.buttons["pairing.retry"].tap()
    XCTAssertTrue(failure.waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Scan the Pixel pairing code"].exists)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["receiver.scan"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Scan the Pixel pairing code"].exists)
  }

  @MainActor func testBackupSourceSettingsReturnToOverview() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 1).waitForExistence(timeout: 20))
    navigation(app, 1).tap()
    let manage = app.buttons["backup.manage_source"]
    for _ in 0..<8 { if manage.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(manage.isHittable)
    XCTAssertTrue(manage.label.contains("More settings"))
    XCTAssertTrue(app.switches["backup.auto_backup"].exists)
    XCTAssertFalse(app.staticTexts["Backup sources"].exists)
    let overview = XCTAttachment(screenshot: app.screenshot())
    overview.name = "Backup overview — automatic new photos switch and More settings"
    overview.lifetime = .keepAlways; add(overview)
    manage.tap()
    XCTAssertTrue(app.staticTexts["page.header.title"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["settings.transfer_concurrency"].exists)
    XCTAssertFalse(app.staticTexts["folder_auto_disabled"].exists)
    XCTAssertFalse(app.staticTexts["folder_auto_enabled"].exists)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Source management — existing and new photos remain distinct"
    screen.lifetime = .keepAlways; add(screen)
    app.buttons["page.header.back"].tap()
    XCTAssertTrue(app.buttons["backup.manage_source"].waitForExistence(timeout: 10))
    XCTAssertTrue(navigation(app, 1).isSelected)
  }

  @MainActor func testReplicaWindowLightDarkAndLargeText() {
    continueAfterFailure = false
    for (appearance, largeText) in [("light", false), ("dark", false), ("light", true), ("dark", true)] {
      let app = XCUIApplication()
      app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
        "-duckAppearance", appearance]
      if largeText {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
      }
      launchIsolated(app)
      XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20))
      for (index, page) in [(1, "backup"), (2, "receiver"), (3, "settings"), (0, "library")] {
        let tab = navigation(app, index)
        XCTAssertTrue(tab.isHittable)
        tab.tap()
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "iOS-replica-\(page)-\(appearance)-\(largeText ? "large" : "normal")"
        screen.lifetime = .keepAlways; add(screen)
      }
      navigation(app, 2).tap()
      let scan = app.buttons["receiver.scan"]
      for _ in 0..<12 { if scan.isHittable { break }; app.swipeUp() }
      XCTAssertTrue(scan.isHittable, "The scan action must remain reachable with enlarged text")
      scan.tap()
      XCTAssertTrue(app.descendants(matching: .any)["pairing.camera_error"].firstMatch.waitForExistence(timeout: 15))
      let screen = XCTAttachment(screenshot: app.screenshot())
      screen.name = "iOS-replica-pairing-\(appearance)-\(largeText ? "large" : "normal")"
      screen.lifetime = .keepAlways; add(screen)
      XCTAssertTrue(app.buttons["取消"].isHittable)
      app.buttons["取消"].tap()
      app.terminate()
    }
  }

  /// Run with the dedicated simulator's camera permission revoked. No hardware
  /// or production account is involved, and the test never leaves the app.
  @MainActor func testPairingPermissionDenialShowsRecovery() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 2).waitForExistence(timeout: 20))
    navigation(app, 2).tap()
    app.buttons["receiver.scan"].tap()
    guard app.staticTexts["Camera access is restricted"].waitForExistence(timeout: 8) else {
      throw XCTSkip("Requires the dedicated simulator camera-denied fixture")
    }
    XCTAssertTrue(app.buttons["Open Settings"].isHittable)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Pairing — camera permission denied — recovery in current sheet"
    screen.lifetime = .keepAlways; add(screen)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["receiver.scan"].waitForExistence(timeout: 10))
  }

  /// Run after importing synthetic images into the isolated simulator only.
  @MainActor func testNativeGallerySelectionAndScrollSurviveTabSwitch() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 0).waitForExistence(timeout: 20))
    navigation(app, 0).tap()
    let request = app.buttons["photos.request"]
    if request.waitForExistence(timeout: 3) {
      request.tap()
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@",
        ["Allow Full Access", "允许完全访问"])).firstMatch
      XCTAssertTrue(allow.waitForExistence(timeout: 10), "Use the real permission sheet on the synthetic simulator")
      allow.tap()
    }
    let grid = app.collectionViews["library.grid"]
    guard grid.waitForExistence(timeout: 8), grid.cells.count > 3 else {
      print("Isolated gallery fixture state: " + app.debugDescription)
      let screen = XCTAttachment(screenshot: app.screenshot())
      screen.name = "Gallery fixture unavailable — actual window"
      screen.lifetime = .keepAlways; add(screen)
      throw XCTSkip("Requires synthetic gallery images and Photos access in the isolated simulator")
    }
    let first = grid.cells.element(boundBy: 0), second = grid.cells.element(boundBy: 1)
    first.press(forDuration: 0.45); second.tap()
    XCTAssertEqual(grid.cells.matching(NSPredicate(format: "selected == true")).count, 2)
    for _ in 0..<6 { grid.swipeUp() }
    let anchor = grid.cells.allElementsBoundByIndex.first { $0.isHittable }
    let position = anchor?.frame.minY
    let identifier = anchor?.identifier
    navigation(app, 3).tap()
    navigation(app, 0).tap()
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    if let identifier, let position {
      let restored = grid.cells[identifier]
      XCTAssertTrue(restored.isHittable)
      XCTAssertEqual(restored.frame.minY, position, accuracy: 3,
        "Returning to the gallery must retain the same asset and native scroll position")
    }
    XCTAssertTrue(app.staticTexts["page.header.title"].label.contains("2"), "Selection count must survive a tab switch")
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Native gallery — synthetic photos — selection and scroll retained"
    screen.lifetime = .keepAlways; add(screen)
  }

  @MainActor func testAppearanceAndDeviceDraftCancellation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    // Appearance must remain writable; a launch-argument defaults override
    // would shadow the persisted value even after the user changes the picker.
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    launchIsolated(app)
    let settings = navigation(app, 3)
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    settings.tap()
    let appearance = app.descendants(matching: .any)["settings.appearance"].firstMatch
    for _ in 0..<8 { if appearance.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(appearance.isHittable)
    appearance.tap()
    let dark = app.buttons["Dark"].firstMatch
    XCTAssertTrue(dark.waitForExistence(timeout: 5))
    dark.tap()
    XCTAssertTrue(appearance.label.contains("Dark") || (appearance.value as? String)?.contains("Dark") == true
      || app.staticTexts["Dark"].exists)
    let darkScreen = XCTAttachment(screenshot: app.screenshot())
    darkScreen.name = "Appearance — actual dark window"; darkScreen.lifetime = .keepAlways; add(darkScreen)
    for _ in 0..<8 { if app.buttons["device.rename"].isHittable { break }; app.swipeDown() }
    app.buttons["device.rename"].tap()
    let field = app.textFields["device.name"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    let original = field.value as? String
    field.tap()
    if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
    let editingScreen = XCTAttachment(screenshot: app.screenshot())
    editingScreen.name = "Device name — actual keyboard focus"; editingScreen.lifetime = .keepAlways; add(editingScreen)
    field.typeText(String(repeating: "x", count: 41))
    XCTAssertFalse(app.buttons["device.name_save"].isEnabled, "A name exceeding 40 Unicode scalars must remain in the editor")
    let invalidScreen = XCTAttachment(screenshot: app.screenshot())
    invalidScreen.name = "Device name — invalid draft retained"; invalidScreen.lifetime = .keepAlways; add(invalidScreen)
    app.buttons["Cancel"].tap()
    app.buttons["device.rename"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, original, "Cancel must not save the rejected draft")
    app.buttons["Cancel"].tap()
  }

  /// Evidence capture only. This deliberately has no visual-fidelity pass claim:
  /// the native windows must be reviewed beside the same-state prototype.
  @MainActor func testFidelityAuditWindows() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-duckAppearance", "light"]
    launchIsolated(app)
    let backup = navigation(app, 1)
    XCTAssertTrue(backup.waitForExistence(timeout: 20)); backup.tap()
    guard app.buttons["backup.pair"].waitForExistence(timeout: 10) else {
      throw XCTSkip("Fidelity evidence requires the unpaired disposable simulator, never an existing user account")
    }
    func capture(_ name: String) {
      // XCTest's screenshot follows its native idle synchronization. Keep the
      // actual hierarchy with the image; rectangles alone are not acceptance.
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = "fidelity-native-" + name; image.lifetime = .keepAlways; add(image)
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "fidelity-native-" + name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    capture("backup-first")
    navigation(app, 0).tap(); capture("library-permission")
    navigation(app, 2).tap(); capture("receiver-first")
    app.buttons["receiver.scan"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["pairing.camera_error"].firstMatch.waitForExistence(timeout: 15))
    capture("pair-camera-unavailable")
    app.buttons["Cancel"].tap()
    navigation(app, 3).tap(); capture("settings-top")
    navigation(app, 1).tap()
    let manage = app.buttons["backup.manage_source"].firstMatch
    for _ in 0..<8 { if manage.exists && manage.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(manage.isHittable); manage.tap()
    XCTAssertTrue(app.staticTexts.matching(identifier: "page.header.title").firstMatch.waitForExistence(timeout: 10))
    capture("backup-settings-unpaired")
    app.buttons["page.header.back"].tap()
    navigation(app, 3).tap()
    let rename = app.buttons["device.rename"]
    if rename.isHittable {
      rename.tap(); XCTAssertTrue(app.textFields["device.name"].waitForExistence(timeout: 10))
      capture("device-name")
      app.buttons["Cancel"].tap()
    }
    let help = app.buttons["settings.help"]
    for _ in 0..<10 { if help.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(help.isHittable); help.tap()
    XCTAssertTrue(app.staticTexts.matching(identifier: "page.header.title").firstMatch.waitForExistence(timeout: 10))
    capture("help-top")
  }

  @MainActor func testFidelityGalleryEvidence() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    navigation(app, 0).tap()
    if app.buttons["photos.request"].waitForExistence(timeout: 3) {
      app.buttons["photos.request"].tap()
      let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(
        NSPredicate(format: "label IN %@", ["Allow Full Access", "允许完全访问"])).firstMatch
      XCTAssertTrue(allow.waitForExistence(timeout: 10)); allow.tap()
    }
    let grid = app.collectionViews["library.grid"]
    guard grid.waitForExistence(timeout: 10), grid.cells.count >= 2 else {
      throw XCTSkip("Requires only the new 32 synthetic RGB fixtures in the dedicated simulator")
    }
    func capture(_ name: String) {
      let image = XCTAttachment(screenshot: app.screenshot()); image.name = "fidelity-native-" + name
      image.lifetime = .keepAlways; add(image)
      let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "fidelity-native-" + name + "-hierarchy"
      hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    capture("library-normal")
    grid.cells.element(boundBy: 0).tap(); grid.cells.element(boundBy: 1).tap(); capture("library-selected")
    for _ in 0..<5 { grid.swipeUp() }
    capture("library-selected-bottom")
  }

  /// Current-page evidence for the second-level layout contract and actual
  /// native controls. Screenshots require side-by-side human visual review.
  @MainActor func testFidelitySecondaryWindows() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    func capture(_ name: String) {
      let image = XCTAttachment(screenshot: app.screenshot()); image.name = "fidelity-native-" + name
      image.lifetime = .keepAlways; add(image)
      let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "fidelity-native-" + name + "-hierarchy"
      hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    func reach(_ id: String) -> XCUIElement {
      let element = app.descendants(matching: .any)[id].firstMatch
      for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
      XCTAssertTrue(element.isHittable, id); return element
    }
    reach("settings.cache").tap()
    XCTAssertTrue(app.buttons["settings.cache_budget"].waitForExistence(timeout: 10))
    capture("cache-settings")
    reach("settings.cache_budget").tap(); XCTAssertTrue(app.buttons["5 GB"].waitForExistence(timeout: 5))
    capture("cache-budget"); app.buttons["5 GB"].tap()
    app.buttons["page.header.back"].tap()
    reach("settings.log_retention").tap()
    XCTAssertTrue(app.buttons["settings.log_days.14"].waitForExistence(timeout: 10))
    capture("log-retention"); app.swipeUp(); capture("log-retention-bottom")
    app.buttons["page.header.back"].tap()
    let language = app.descendants(matching: .any)["settings.language"].firstMatch
    for _ in 0..<8 { if language.isHittable { break }; app.swipeDown() }
    XCTAssertTrue(language.isHittable)
    XCTAssertFalse(app.buttons["settings.language"].exists, "App language is a read-only current value, not an empty push workflow")
    capture("language-readonly")
    reach("settings.activity_log").tap()
    let export = app.buttons["activity.export"]
    XCTAssertTrue(export.waitForExistence(timeout: 10))
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export); waitForExpectations(timeout: 10)
    capture("activity-log")
    let details = app.buttons["activity.details"].firstMatch
    for _ in 0..<8 { if details.exists && details.isHittable { break }; app.swipeUp() }
    if details.exists && details.isHittable {
      details.tap()
      XCTAssertTrue(app.descendants(matching: .any)["activity.detail"].firstMatch.waitForExistence(timeout: 10))
      capture("activity-log-detail")
      XCTAssertTrue(app.buttons["activity.detail.done"].waitForExistence(timeout: 10))
      app.buttons["activity.detail.done"].tap()
    }
    XCTAssertTrue(export.isHittable, "Export stays in the fixed footer when records scroll")
    export.tap()
    XCTAssertTrue(app.buttons["activity.export_share"].waitForExistence(timeout: 10))
    capture("diagnostic-share-ready")
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(app.buttons["activity.done"].waitForExistence(timeout: 10)); app.buttons["activity.done"].tap()
    reach("settings.help").tap(); app.swipeUp(); capture("help-middle")
    app.swipeUp(); app.swipeUp(); capture("help-bottom")
  }

  @MainActor func testPreferenceRowHeightsAndValueAlignment() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    let appearance = app.buttons["settings.appearance"]
    XCTAssertTrue(appearance.waitForExistence(timeout: 10))
    let language = app.descendants(matching: .any)["settings.language"].firstMatch
    XCTAssertEqual(app.staticTexts["Appearance"].frame.midY, appearance.frame.midY, accuracy: 2)
    XCTAssertEqual(app.staticTexts["Appearance"].frame.midY - language.frame.midY, -53, accuracy: 3)
    recordWindow(app, "Uniform settings rows — appearance and language")
    reachSettingsEntry(app, "settings.cache").tap()
    let budget = app.descendants(matching: .any)["settings.cache_budget"].firstMatch
    XCTAssertTrue(budget.waitForExistence(timeout: 10))
    XCTAssertGreaterThanOrEqual(budget.frame.height, 51.5)
    let used = app.staticTexts["Temporary files used"], maximum = app.staticTexts["Maximum cache size"]
    XCTAssertEqual(maximum.frame.midY - used.frame.midY, 53, accuracy: 3)
    XCTAssertEqual(budget.frame.midY, maximum.frame.midY, accuracy: 2)
    let free = app.staticTexts["Free space on this device"], reserve = app.staticTexts["Keep free on this device"]
    XCTAssertEqual(reserve.frame.midY - free.frame.midY, 53, accuracy: 3)
    recordWindow(app, "Uniform cache rows — static values and menus")
    let choice = budget.label.contains("5 GB") ? "10 GB" : "5 GB"
    budget.tap(); XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5))
    XCTAssertTrue(maximum.exists); app.buttons[choice].firstMatch.tap()
    XCTAssertTrue(budget.waitForExistence(timeout: 10))
    XCTAssertEqual(maximum.frame.midY - used.frame.midY, 53, accuracy: 3)
    app.buttons["page.header.back"].tap()
    reachSettingsEntry(app, "settings.log_retention").tap()
    XCTAssertTrue(app.buttons["settings.log_days.1"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["settings.log_days.1"].frame.height, 52, accuracy: 2)
    recordWindow(app, "Uniform log retention choice rows")
  }

  @MainActor func testSettingsMenuAnchorsAndAbout() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    func capture(_ name: String) {
      let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
      attachment.lifetime = .keepAlways; add(attachment)
    }
    let appearance = app.buttons["settings.appearance"]
    XCTAssertTrue(appearance.waitForExistence(timeout: 10)); appearance.tap()
    XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Appearance"].exists)
    capture("Appearance menu — title remains on the page")
    app.buttons["Light"].firstMatch.tap()
    let cache = app.buttons["settings.cache"]
    for _ in 0..<8 { if cache.isHittable { break }; app.swipeUp() }
    cache.tap()
    let budget = app.buttons["settings.cache_budget"]
    XCTAssertTrue(budget.waitForExistence(timeout: 10)); budget.tap()
    XCTAssertTrue(app.buttons["5 GB"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Maximum cache size"].exists)
    capture("Cache menu — title remains on the page")
    app.staticTexts["page.header.title"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    app.buttons["page.header.back"].tap()
    let about = app.buttons["settings.about"]
    for _ in 0..<8 { if about.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(about.isHittable); about.tap()
    XCTAssertTrue(app.buttons["about.website"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["App version"].exists)
    XCTAssertFalse(app.staticTexts["Interface version"].exists)
    capture("About — real version and official website")
    app.buttons["page.header.back"].tap()
    navigation(app, 1).tap()
    let more = app.buttons["backup.manage_source"]
    for _ in 0..<8 { if more.isHittable { break }; app.swipeUp() }
    more.tap()
    let concurrency = app.buttons["settings.transfer_concurrency"]
    XCTAssertTrue(concurrency.waitForExistence(timeout: 10)); concurrency.tap()
    XCTAssertTrue(app.buttons["4"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Concurrent uploads"].exists)
    capture("Concurrency menu — explanation remains on the page")
    app.staticTexts["page.header.title"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    app.buttons["page.header.back"].tap()
  }

  @MainActor func testLargeTextActivityLatestControls() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-duckAppearance", "dark",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    let log = app.buttons["settings.activity_log"]
    for _ in 0..<12 { if log.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(log.isHittable); log.tap()
    let latest = app.buttons["activity.latest"]
    XCTAssertTrue(latest.waitForExistence(timeout: 10)); XCTAssertTrue(latest.isHittable)
    let position = latest.frame.minY
    latest.tap()
    XCTAssertTrue(app.buttons["activity.details"].firstMatch.isHittable)
    XCTAssertTrue(latest.isHittable)
    XCTAssertEqual(latest.frame.minY, position, accuracy: 2)
    let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Activity latest — dark maximum text"
    image.lifetime = .keepAlways; add(image)
  }

  /// Begin on the physical leading edge. A center swipe is an ordinary scroll
  /// gesture and would not prove UINavigationController interactive pop.
  @MainActor private func edgeBack(_ app: XCUIApplication, complete: Bool = true) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.48))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: complete ? 0.85 : 0.12, dy: 0.48))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow,
      thenHoldForDuration: complete ? 0.1 : 0.5)
  }
  @MainActor private func reachSettingsEntry(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    let target = app.buttons[id].firstMatch
    for _ in 0..<12 { if target.exists && target.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(target.isHittable, "Expected live Settings entry: " + id)
    return target
  }

  @MainActor func testNativeEdgeBackPreservesSettingsStack() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    let cache = reachSettingsEntry(app, "settings.cache")
    let parentPosition = cache.frame.minY
    cache.tap()
    XCTAssertTrue(app.buttons["settings.cache_budget"].waitForExistence(timeout: 10))
    // A slow, short interaction must cancel through UIKit, retaining this page.
    edgeBack(app, complete: false)
    XCTAssertTrue(app.buttons["settings.cache_budget"].waitForExistence(timeout: 10))
    let cancelled = XCTAttachment(screenshot: app.screenshot()); cancelled.name = "Native edge pop — cancelled on cache"
    cancelled.lifetime = .keepAlways; add(cancelled)
    edgeBack(app)
    XCTAssertTrue(app.buttons["settings.cache"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["page.header.title"].label, "Settings")
    XCTAssertEqual(app.buttons["settings.cache"].frame.minY, parentPosition, accuracy: 5,
      "Native pop must preserve the parent Settings scroll location")
    XCTAssertFalse(app.buttons["page.header.back"].exists, "Returning to the stack root must not leave a phantom back action")
    // Root-edge dragging must stay at root, without popping a nonexistent page.
    edgeBack(app)
    XCTAssertEqual(app.staticTexts["page.header.title"].label, "Settings")
    let returned = XCTAttachment(screenshot: app.screenshot()); returned.name = "Native edge pop — parent state retained"
    returned.lifetime = .keepAlways; add(returned)
  }

  @MainActor func testNativeEdgeBackFromDeeperCachePage() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    reachSettingsEntry(app, "settings.cache").tap()
    XCTAssertTrue(app.buttons["settings.cache_budget"].waitForExistence(timeout: 10))
    let reclaim = app.buttons["settings.reclaim_cache"]
    for _ in 0..<10 { if reclaim.exists && reclaim.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(reclaim.exists && reclaim.isHittable, "Cache inspection is a genuine read-only third-level entry even when cache is empty")
    let parentPosition = reclaim.frame.minY
    reclaim.tap()
    XCTAssertTrue(app.buttons["settings.reclaim_confirm"].waitForExistence(timeout: 10))
    edgeBack(app, complete: false)
    XCTAssertTrue(app.buttons["settings.reclaim_confirm"].waitForExistence(timeout: 10))
    edgeBack(app)
    XCTAssertTrue(app.buttons["settings.reclaim_cache"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["settings.reclaim_cache"].frame.minY, parentPosition, accuracy: 5)
    XCTAssertFalse(app.buttons["settings.reclaim_confirm"].exists)
    edgeBack(app)
    XCTAssertEqual(app.staticTexts["page.header.title"].label, "Settings")
  }

  @MainActor func testPushReturnAndModalCancelDoneAreDistinct() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    app.buttons["device.rename"].tap()
    let field = app.textFields["device.name"]
    XCTAssertTrue(field.waitForExistence(timeout: 10)); let original = field.value as? String
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["device.rename"].waitForExistence(timeout: 10))
    app.buttons["device.rename"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 10)); XCTAssertEqual(field.value as? String, original)
    app.buttons["Cancel"].tap()
    let log = reachSettingsEntry(app, "settings.activity_log"); let position = log.frame.minY
    log.tap(); XCTAssertTrue(app.buttons["activity.done"].waitForExistence(timeout: 10))
    app.buttons["activity.done"].tap()
    XCTAssertTrue(app.buttons["settings.activity_log"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["settings.activity_log"].frame.minY, position, accuracy: 5)
    XCTAssertEqual(app.staticTexts["page.header.title"].label, "Settings")
  }

  @MainActor func testLibraryDragEdgeScroll() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 0).waitForExistence(timeout: 20)); navigation(app, 0).tap()
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    grid.swipeDown();grid.swipeDown()
    guard let first = grid.cells.allElementsBoundByIndex.first(where: { $0.isHittable && $0.frame.minY > grid.frame.minY }) else { throw XCTSkip("Requires synthetic gallery") }
    let id = first.identifier
    let edge = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96))
    first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 1.5)
    XCTAssertTrue(app.buttons["library.select_mode"].exists)
    XCTAssertFalse(grid.cells[id].isHittable, "Holding at the safe edge scrolls the initial asset out of view")
    XCTAssertGreaterThan(grid.cells.matching(NSPredicate(format: "selected == true")).count, 3)
    let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Native range selection after edge scrolling"; image.lifetime = .keepAlways; add(image)
  }

  @MainActor func testLibraryLongPressDragRange() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 0).waitForExistence(timeout: 20)); navigation(app, 0).tap()
    let grid = app.collectionViews["library.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    let cells = grid.cells.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY > grid.frame.minY }
    guard cells.count >= 4 else { throw XCTSkip("Requires isolated synthetic gallery") }
    let first = cells[0], fourth = cells[3]
    first.press(forDuration: 0.5, thenDragTo: fourth, withVelocity: .slow, thenHoldForDuration: 0)
    XCTAssertTrue(app.buttons["library.select_mode"].waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(grid.cells.matching(NSPredicate(format: "selected == true")).count, 4)
    let backup = app.buttons["calendar.backup_selected"]
    XCTAssertTrue(backup.exists);XCTAssertLessThan(backup.frame.maxY,220,"Backup stays beside the filter in the native header")
    let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Native continuous selection toolbar"; image.lifetime = .keepAlways; add(image)
    first.press(forDuration: 0.5, thenDragTo: fourth, withVelocity: .slow, thenHoldForDuration: 0)
    XCTAssertEqual(grid.cells.matching(NSPredicate(format: "selected == true")).count, 0, "Dragging from an already selected item removes that range")
  }

  @MainActor func testLibraryBrowseSelectFixedAction() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 0).waitForExistence(timeout: 20)); navigation(app, 0).tap()
    let request = app.buttons["photos.request"]
    if request.waitForExistence(timeout: 2) {
      request.tap()
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@",
        ["Allow Full Access", "允许完全访问"])).firstMatch
      XCTAssertTrue(allow.waitForExistence(timeout: 10), "Authorize only the isolated synthetic library")
      allow.tap()
    }
    let grid = app.collectionViews["library.grid"]
    guard grid.waitForExistence(timeout: 10), grid.cells.count >= 2 else {
      throw XCTSkip("Requires the isolated simulator's synthetic photo library; this test never imports user photos")
    }
    let mode = app.buttons["library.select_mode"]
    XCTAssertTrue(mode.isHittable,"Browsing offers an explicit Select action")
    XCTAssertFalse(app.buttons["calendar.backup_selected"].exists, "Browsing must not show the selected-upload action")
    let first = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable })
    let photoID = first.identifier, position = first.frame.minY
    let browseImage = XCTAttachment(screenshot: app.screenshot())
    browseImage.name = "Library browsing — native grid under floating tab bar"
    browseImage.lifetime = .keepAlways; add(browseImage)
    if #available(iOS 26.0, *) {
      XCTAssertGreaterThan(grid.frame.maxY, navigation(app, 0).frame.minY,
        "The real collection viewport extends beneath the native floating tabs")
    }
    first.tap()
    XCTAssertTrue(app.buttons["library.preview.close"].waitForExistence(timeout: 10), "Default browsing opens the native photo preview")
    app.buttons["library.preview.close"].tap()
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    XCTAssertTrue(grid.cells[photoID].isHittable)
    XCTAssertEqual(grid.cells[photoID].frame.minY, position, accuracy: 3, "Preview dismissal retains the same scroll anchor")
    XCTAssertEqual(mode.label,"Select")
    try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable }).press(forDuration: 0.45)
    XCTAssertTrue(mode.waitForExistence(timeout: 10)); XCTAssertEqual(mode.label, "Done")
    XCTAssertFalse(app.buttons["library.preview.close"].exists, "Long press selects instead of also opening preview")
    let upload = app.buttons["calendar.backup_selected"]
    XCTAssertTrue(upload.waitForExistence(timeout: 10))
    for _ in 0..<6 {
      grid.swipeUp()
      XCTAssertTrue(upload.exists,"Selection action stays fixed while the native collection scrolls")
      XCTAssertTrue(app.buttons["calendar.review_selected"].label.contains("1"), "The review control shows the selected count")
    }
    let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Library selection — fixed footer after continuous scrolling"
    screenshot.lifetime = .keepAlways; add(screenshot)
    mode.tap();XCTAssertEqual(mode.label,"Select")
    XCTAssertFalse(app.buttons["calendar.backup_selected"].exists)
    XCTAssertFalse(app.buttons["calendar.review_selected"].exists)
    // The action may be disabled without pairing; no transmission is invoked.
  }

  @MainActor func testSettingsAndReceiverSimplificationBD25() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-duckAppearance", "light"]
    launchIsolated(app)
    XCTAssertTrue(navigation(app, 3).waitForExistence(timeout: 20)); navigation(app, 3).tap()
    XCTAssertFalse(app.buttons["settings.backup"].exists, "Source strategy has one owner under Backup")
    XCTAssertFalse(app.staticTexts["Backup sources"].exists)
    XCTAssertFalse(app.staticTexts["Choose a name that helps you recognize this device. Renaming keeps existing connections and backup records."].exists)
    let language = app.descendants(matching: .any)["settings.language"].firstMatch
    XCTAssertTrue(language.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["settings.language"].exists)
    let cache = reachSettingsEntry(app, "settings.cache")
    let previousCacheIntroduction = "Before sending, BackupDuck prepares originals and upload files on this iPhone, iPad or Mac. These temporary copies use local storage. These settings do not control receiver storage."
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", previousCacheIntroduction)).count, 0)
    cache.tap()
    XCTAssertTrue(app.buttons["settings.cache_budget"].waitForExistence(timeout: 10))
    let emptyCacheNotice = "No relay cache is currently stored. Nothing to reclaim."
    XCTAssertFalse(app.staticTexts[emptyCacheNotice].exists, "Empty-cache results belong only to the reclaim details")
    XCTAssertFalse(app.staticTexts["settings.reclaim_empty"].exists)
    let budget = app.buttons["settings.cache_budget"]
    XCTAssertTrue(budget.isHittable); XCTAssertGreaterThanOrEqual(budget.frame.height, 43.5)
    let priorBudgetLabel = budget.label
    let headerFrame = app.staticTexts["page.header.title"].frame
    let dismissMenu = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
      dx: headerFrame.midX - app.frame.minX, dy: headerFrame.midY - app.frame.minY))
    let cacheImage = XCTAttachment(screenshot: app.screenshot())
    cacheImage.name = "v1.2.5 cache settings — no empty-cache status; whole-row size menu"
    cacheImage.lifetime = .keepAlways; add(cacheImage)
    budget.tap()
    let budgetOption = app.buttons["5 GB"]
    XCTAssertTrue(budgetOption.waitForExistence(timeout: 5), "The row opens the native size menu")
    // UIKit owns the popup item's geometry (its accessibility frame can be
    // 42pt). The custom settings row above owns the 52pt minimum target.
    XCTAssertTrue(budgetOption.isHittable)
    let menuImage = XCTAttachment(screenshot: app.screenshot())
    menuImage.name = "v1.2.5 native cache size menu — cancel retains current value"
    menuImage.lifetime = .keepAlways; add(menuImage)
    dismissMenu.tap()
    XCTAssertTrue(budget.waitForExistence(timeout: 5)); XCTAssertTrue(budget.isHittable)
    XCTAssertEqual(budget.label, priorBudgetLabel, "Cancelling never changes the saved budget")
    XCTAssertEqual(app.staticTexts["page.header.title"].label, "Local cache", "Cancel keeps the current parent page")
    XCTAssertFalse(app.staticTexts[emptyCacheNotice].exists)
    XCTAssertTrue(app.staticTexts["Preparation cache"].exists)
    XCTAssertTrue(app.staticTexts["Free-space reserve"].exists || app.buttons["settings.min_free"].exists)
    let safeText = "Only verified received copies are reclaimed. Pending or in-use copies and photo library originals are kept; cloud backup is separate."
    let inspect = app.buttons["settings.reclaim_cache"]
    for _ in 0..<10 { if inspect.exists && inspect.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(inspect.isHittable)
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", safeText)).count, 1)
    inspect.tap(); XCTAssertTrue(app.buttons["settings.reclaim_confirm"].waitForExistence(timeout: 10))
    // This path is read-only until the explicit action; the test never reclaims.
    app.buttons["page.header.back"].tap(); app.buttons["page.header.back"].tap()
    reachSettingsEntry(app, "settings.log_retention").tap()
    let baseline = app.buttons["settings.log_days.1"]
    XCTAssertTrue(baseline.waitForExistence(timeout: 10)); baseline.tap()
    expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: baseline)
    waitForExpectations(timeout: 10)
    let day = app.buttons["settings.log_days.14"]
    XCTAssertTrue(day.waitForExistence(timeout: 10)); XCTAssertGreaterThanOrEqual(day.frame.height, 44)
    day.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5)).tap()
    let selected = NSPredicate(format: "selected == true")
    expectation(for: selected, evaluatedWith: day); waitForExpectations(timeout: 10)
    XCTAssertFalse(baseline.isSelected, "The trailing whitespace click must change the saved choice, not merely reselect the default")
    let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "BD25 log retention — trailing whitespace selects row"
    screen.lifetime = .keepAlways; add(screen)
    app.buttons["page.header.back"].tap()
    navigation(app, 2).tap()
    XCTAssertFalse(app.buttons["receiver.help"].exists, "Receiver has no duplicate pure-help entry")
    navigation(app, 3).tap()
    reachSettingsEntry(app, "settings.help").tap()
    XCTAssertTrue(app.otherElements["settings.help.content"].exists || app.staticTexts["page.header.title"].exists)
    app.buttons["page.header.back"].tap()

  }

}
