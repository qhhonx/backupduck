import XCTest

final class InteractionTests: XCTestCase {
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
