import XCTest

final class InteractionTests: XCTestCase {
    func testSelectedReviewReusesViewerWithinBatch() {
        let app = XCUIApplication(); app.launch(); app.buttons["显示所选内容"].tap()
        let grid = app.collectionViews["reference.selected_grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5)); XCTAssertEqual(grid.cells.count,3)
        XCTAssertEqual(grid.cells.element(boundBy: 0).frame.minY,grid.cells.element(boundBy: 2).frame.minY,accuracy: 1)
        app.buttons["reference.selected_browse"].tap()
        XCTAssertEqual(app.collectionViews["preview.filmstrip"].cells.count,3)
        app.scrollViews["preview.pager"].swipeLeft()
        XCTAssertTrue(app.staticTexts["14:01 · 示例 2"].waitForExistence(timeout: 3))
        app.buttons["返回图库"].tap(); XCTAssertTrue(grid.waitForExistence(timeout: 3))
    }
    func testScopeChoicesUseStableRowsAndThreeColumnCovers() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tables.cells.element(boundBy: 0).tap()
        let row = app.tables.cells.element(boundBy: 0), frame = row.frame
        row.tap(); XCTAssertEqual(row.frame,frame); row.tap(); XCTAssertEqual(row.frame,frame)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tables.cells.element(boundBy: 1).tap()
        let covers = app.collectionViews.firstMatch.cells
        XCTAssertTrue(covers.element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertEqual(covers.element(boundBy: 0).frame.minY,covers.element(boundBy: 2).frame.minY,accuracy: 1)
        covers.element(boundBy: 0).tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Three-column album choices"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testContinuousPagingScrubbingInformationAndReturn() {
        let app = XCUIApplication(); app.launch()
        let grid = app.collectionViews["preview.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5)); grid.cells.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["14:01 · 示例 2"].waitForExistence(timeout: 3))
        let pager = app.scrollViews["preview.pager"]
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85,dy: 0.5)).press(forDuration: 0.05,thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.1,dy: 0.5)),withVelocity: .slow,thenHoldForDuration: 0)
        XCTAssertTrue(app.staticTexts["14:02 · 示例 3"].waitForExistence(timeout: 3))
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.55,dy: 0.5)).press(forDuration: 0.05,thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.49,dy: 0.5)),withVelocity: .slow,thenHoldForDuration: 0.2)
        XCTAssertTrue(app.staticTexts["14:02 · 示例 3"].exists)
        let strip = app.collectionViews["preview.filmstrip"]
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.8,dy: 0.5)).press(forDuration: 0.05,thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: 0.2,dy: 0.5)),withVelocity: .slow,thenHoldForDuration: 0.2)
        XCTAssertFalse(app.staticTexts["14:02 · 示例 3"].exists)
        pager.swipeUp()
        XCTAssertTrue(app.staticTexts["拍摄位置 · 示例位置"].waitForExistence(timeout: 3))
        app.buttons["关闭信息"].tap()
        XCTAssertTrue(app.buttons["返回图库"].waitForExistence(timeout: 3))
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.35)).press(forDuration: 0.05,thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.9)),withVelocity: .slow,thenHoldForDuration: 0.1)
        XCTAssertTrue(grid.waitForExistence(timeout: 3))
    }
}
