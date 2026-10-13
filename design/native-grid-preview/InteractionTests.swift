import XCTest

final class GridInteractions: XCTestCase {
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
}
