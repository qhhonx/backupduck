import XCTest

final class GridInteractions: XCTestCase {
  func testCalendarCoverVideoAndPinchHierarchy() {
    continueAfterFailure = false
    let app = XCUIApplication(); app.launchArguments = ["--movie-cover"]; app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 5)); grid.swipeDown()
    app.buttons["Years"].tap()
    let playing = grid.cells.matching(NSPredicate(format: "value == %@", "Muted video preview")).firstMatch
    XCTAssertTrue(playing.waitForExistence(timeout: 5), "The generated calendar cover renders actual muted video")
    let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Generated year-cover movie"; screenshot.lifetime = .keepAlways; add(screenshot)
    grid.pinch(withScale: 1.5, velocity: 0.6)
    XCTAssertTrue(app.buttons["Months"].isSelected)
    grid.pinch(withScale: 1.5, velocity: 0.6)
    XCTAssertTrue(app.buttons["All"].isSelected)
  }

  func testSnapshotZoomAndRepeatedLibraryTab() {
    continueAfterFailure = false
    let app = XCUIApplication(); app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    grid.swipeDown()
    if #available(iOS 26.0, *) { app.buttons["Library"].tap() }
    else { app.buttons["calendar.navigation"].tap() }
    app.tabBars.buttons["Library"].tap()
    let newest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "1,440"), object: app.staticTexts["calendar.subtitle"])
    XCTAssertEqual(XCTWaiter.wait(for: [newest], timeout: 5), .completed)
    grid.swipeDown()
    for columns in [5, 15, 31] {
      grid.pinch(withScale: 0.55, velocity: -0.7)
      let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "\(columns) columns"), object: grid)
      XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, "Actual settled value: \(String(describing: grid.value))")
    }
    XCTAssertFalse(app.staticTexts["calendar.subtitle"].isHittable)
    grid.pinch(withScale: 0.55, velocity: -0.7)
    let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "31 columns"), object: grid)
    XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed)
    let captions = app.staticTexts.matching(identifier: "calendar.period_heading").allElementsBoundByIndex.filter { $0.isHittable }.sorted { $0.frame.minY < $1.frame.minY }
    for i in 1..<captions.count { XCTAssertGreaterThanOrEqual(captions[i].frame.minY, captions[i - 1].frame.maxY) }
    let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Terminal overview with separated captions"; image.lifetime = .keepAlways; add(image)
    grid.pinch(withScale: 1.7, velocity: 0.7)
    let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "15 columns"), object: grid)
    XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
  }

  func testNativeTabMinimization() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    func record(_ name: String) {
      let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    record("Native tabs — newest edge")
    grid.swipeDown()
    record("Native tabs — scroll into history")
    XCTAssertTrue(app.buttons["Years"].isHittable)
    XCTAssertFalse(app.tabBars.buttons["Backup"].isHittable)
    let remains = XCTNSPredicateExpectation(predicate:NSPredicate(format:"hittable == true"),object:app.buttons["Years"])
    XCTAssertEqual(XCTWaiter.wait(for:[remains],timeout:2),.completed)
    Thread.sleep(forTimeInterval:1.2)
    XCTAssertTrue(app.buttons["Months"].isHittable,"Period controls persist while the native icon is compact")
    app.buttons["Library"].tap()
    record("Native tabs — native circle expands navigation")
    XCTAssertTrue(app.tabBars.buttons["Backup"].isHittable)
    XCTAssertFalse(app.buttons["Years"].isHittable)
  }

  func testSingleChromeAndFunctionalFilters() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["Backup"].isHittable)
    grid.swipeDown()
    XCTAssertTrue(app.buttons["Years"].isHittable)
    XCTAssertFalse(
      app.tabBars.buttons["Backup"].isHittable, "Calendar browsing replaces the full navigation bar"
    )
    if #available(iOS 26.0, *) { app.buttons["Library"].tap() }
    else { app.buttons["calendar.navigation"].tap() }
    XCTAssertTrue(app.tabBars.buttons["Backup"].isHittable)
    XCTAssertFalse(app.buttons["Years"].isHittable)
    app.buttons["calendar.options"].tap()
    XCTAssertTrue(app.buttons["Videos"].waitForExistence(timeout: 5))
    app.buttons["Videos"].tap()
    XCTAssertFalse(app.staticTexts["calendar.subtitle"].label.contains("1,440"))
    app.buttons["calendar.select"].tap()
    grid.cells.allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
    XCTAssertTrue(app.buttons["calendar.review_selected"].isHittable)
    XCTAssertFalse(app.tabBars.buttons["Backup"].isHittable)
    let selected = XCTAttachment(screenshot: app.screenshot())
    selected.name = "One bottom control surface — readable selected count"
    selected.lifetime = .keepAlways
    add(selected)
  }
  func testLongLibrarySnapshotsRetainNewestMediaWindow() {
    continueAfterFailure = false
    let app = XCUIApplication(); app.launchArguments = ["--long-library"]; app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout:10))
    for columns in [5,15,31] {
      grid.pinch(withScale:0.55,velocity:-0.7)
      let settled = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","\(columns) columns"),object:grid)
      XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:5),.completed)
      XCTAssertTrue(grid.cells["calendar.asset.example-54999"].exists,"The viewport remains at the newest end of 55k individually numbered photos")
      let frame = XCTAttachment(screenshot:app.screenshot()); frame.name = "55k newest window — \(columns) columns"; frame.lifetime = .keepAlways; add(frame)
    }
    grid.swipeDown(); grid.swipeDown()
    let frame = XCTAttachment(screenshot:app.screenshot()); frame.name = "55k dense history — bounded thumbnail window"; frame.lifetime = .keepAlways; add(frame)
  }

  func testPeriodButtonsKeepLatestMonthAndYear() {
    continueAfterFailure = false
    let app = XCUIApplication(); app.launchArguments = ["--long-library"]; app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout:10)); grid.swipeDown()
    for mode in ["Months","Years","All","Years"] {
      app.buttons[mode].tap()
      let recent = grid.cells.allElementsBoundByIndex.filter { $0.isHittable }.compactMap { Int($0.identifier.split(separator:"-").last ?? "") }.max() ?? 0
      XCTAssertGreaterThan(recent,54000,"Buttons preserve the recent period rather than the oldest cover")
      let a = XCTAttachment(screenshot:app.screenshot()); a.name = "Recent period — \(mode)"; a.lifetime = .keepAlways; add(a)
    }
    app.buttons["Library"].tap()
    XCTAssertTrue(app.tabBars.buttons["Backup"].isHittable)
    XCTAssertFalse(app.buttons["Years"].isHittable)
  }

  func testLongLibraryCalendarAndDenseGrid() {
    let app = XCUIApplication()
    app.launchArguments = ["--long-library"]
    app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    grid.swipeDown()
    app.buttons["Years"].tap()
    let year = grid.cells.allElementsBoundByIndex.first(where: { $0.isHittable })!
    year.tap()
    let day = grid.cells.allElementsBoundByIndex.first(where: { $0.isHittable })!
    day.tap()
    for _ in 0..<3 {
      app.buttons["calendar.options"].tap()
      app.buttons["Display Options"].tap()
      app.buttons["Zoom Out"].tap()
    }
    grid.swipeDown()
    grid.pinch(withScale: 1.6, velocity: 0.5)
    XCTAssertTrue(app.buttons["calendar.select"].isHittable)
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "55k synthetic library — dense browsing"
    image.lifetime = .keepAlways
    add(image)
  }
  func testCalendarHierarchyDensityAndSelection() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["calendar.subtitle"].label.contains("1,440"))
    grid.swipeDown()
    let years = app.buttons["Years"]
    XCTAssertTrue(years.waitForExistence(timeout: 5))
    years.tap()
    XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 5))
    let year = XCTAttachment(screenshot: app.screenshot())
    year.name = "Years covers"
    year.lifetime = .keepAlways
    add(year)
    grid.cells.allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
    XCTAssertTrue(app.segmentedControls["calendar.level"].waitForExistence(timeout: 5))
    let month = XCTAttachment(screenshot: app.screenshot())
    month.name = "Month day mosaic"
    month.lifetime = .keepAlways
    add(month)
    grid.cells.allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
    let all = XCTAttachment(screenshot: app.screenshot())
    all.name = "All after day cover"
    all.lifetime = .keepAlways
    add(all)
    grid.pinch(withScale: 0.6, velocity: -0.5)
    app.buttons["calendar.select"].tap()
    let cell = grid.cells.allElementsBoundByIndex.first(where: { $0.isHittable })!
    cell.tap()
    XCTAssertTrue(app.buttons["calendar.review_selected"].label.contains("1"))
    app.buttons["calendar.review_selected"].tap()
    XCTAssertTrue(app.collectionViews["calendar.selected_grid"].waitForExistence(timeout: 5))
    let selected = XCTAttachment(screenshot: app.screenshot())
    selected.name = "Selected items review"
    selected.lifetime = .keepAlways
    add(selected)
  }
  func testCompactExpansionPreservesViewportAndExpandedReselectionReturnsNewest() throws {
    continueAfterFailure = false
    let app = XCUIApplication(); app.launch()
    let grid = app.collectionViews["calendar.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    grid.swipeDown()
    XCTAssertTrue(app.buttons["Years"].waitForExistence(timeout: 5))
    let focal = try XCTUnwrap(grid.cells.allElementsBoundByIndex.first { $0.isHittable && $0.frame.midY > 300 && $0.frame.midY < 600 })
    let identifier = focal.identifier, y = focal.frame.midY
    app.buttons["Library"].tap()
    XCTAssertTrue(app.tabBars.buttons["Backup"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.8)
    XCTAssertEqual(grid.cells[identifier].frame.midY, y, accuracy: 1,
      "Expanding the compact icon must not scroll the library")
    app.tabBars.buttons["Library"].tap()
    let newest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "1,440"),
      object: app.staticTexts["calendar.subtitle"])
    XCTAssertEqual(XCTWaiter.wait(for: [newest], timeout: 5), .completed)
    let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Expanded Library reselect — newest edge"; screen.lifetime = .keepAlways; add(screen)
  }

}
