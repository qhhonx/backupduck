import XCTest

final class ProPageScrollTests: XCTestCase {
  @MainActor func testInitialPurchaseAndScrolledTermsClearNativeBars() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "app.backupduck.catalog")
    app.launchArguments = ["-scenario", "subscription.settings-nonmember-detail", "-capture",
      "-appearance", "light", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let purchase = app.buttons["subscription.purchase"]
    let terms = app.buttons["subscription.terms"]
    XCTAssertTrue(purchase.waitForExistence(timeout: 15))
    XCTAssertTrue(terms.exists)
    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.exists)
    XCTAssertTrue(purchase.isHittable)
    XCTAssertGreaterThanOrEqual(purchase.frame.minY, app.navigationBars.firstMatch.frame.maxY)
    XCTAssertLessThanOrEqual(purchase.frame.maxY, tabBar.frame.minY)
    let monthly = app.buttons["subscription.plan.monthly"]
    let annual = app.buttons["subscription.plan.annual"]
    XCTAssertTrue(monthly.isHittable)
    XCTAssertTrue(annual.isHittable)
    XCTAssertTrue(annual.isSelected)
    XCTAssertLessThan(annual.frame.minY, monthly.frame.minY)
    XCTAssertTrue(annual.label.contains("12.00"))
    XCTAssertTrue(annual.label.contains("1.00"))
    XCTAssertTrue(annual.label.contains("省 50%"))
    monthly.tap()
    XCTAssertTrue(monthly.isSelected)
    annual.tap()
    XCTAssertTrue(annual.isSelected)
    XCTAssertFalse(monthly.isSelected)
    attach(app, name: "pro-native-initial-purchase")
    purchase.tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不会创建订阅")).firstMatch.exists)
    attach(app, name: "pro-native-simulated-purchase")
    app.alerts.firstMatch.buttons.firstMatch.tap()

    let scroll = app.scrollViews.firstMatch
    XCTAssertTrue(scroll.exists)
    // The scroll view extends under the pinned plans, so swipe within the visible content.
    let visibleTop = app.navigationBars.firstMatch.frame.maxY
    let visibleHeight = annual.frame.minY - visibleTop
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let start = origin.withOffset(CGVector(dx: scroll.frame.midX, dy: visibleTop + visibleHeight * 0.75))
    let end = origin.withOffset(CGVector(dx: scroll.frame.midX, dy: visibleTop + visibleHeight * 0.25))
    for _ in 0..<3 { start.press(forDuration: 0.05, thenDragTo: end) }
    XCTAssertTrue(purchase.isHittable)
    XCTAssertTrue(terms.isHittable)
    let record = "purchase=\(purchase.frame), terms=\(terms.frame), tabBar=\(tabBar.frame), app=\(app.frame)"
    let frames = XCTAttachment(string: record)
    frames.name = "pro-native-scroll-end-frames"; frames.lifetime = .keepAlways; add(frames)
    attach(app, name: "pro-native-scroll-end")
    XCTAssertLessThanOrEqual(purchase.frame.maxY, tabBar.frame.minY, record)
    XCTAssertLessThanOrEqual(terms.frame.maxY, annual.frame.minY, record)

    terms.tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    app.alerts.firstMatch.buttons.firstMatch.tap()
    print("PRO_NATIVE_SCROLL_END \(record)")
  }

  @MainActor func testSubscriptionStateReviewScreenshots() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "app.backupduck.catalog")
    for state in ["active", "renewal-off"] {
      app.launchArguments = ["-scenario", "subscription.settings-" + state, "-capture",
        "-appearance", "light", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      let entry = app.buttons["subscription.settings.entry"]
      XCTAssertTrue(entry.waitForExistence(timeout: 15))
      attach(app, name: "settings-" + state + "-entry")
      entry.tap()
      XCTAssertTrue(app.buttons["subscription.status.action"].waitForExistence(timeout: 10))
      attach(app, name: "settings-" + state + "-detail")
      app.terminate()
    }
    for state in ["running", "empty", "failed"] {
      app.launchArguments = ["-scenario", "subscription.restore-" + state, "-capture",
        "-appearance", "light", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      let purchase = app.buttons["subscription.purchase"]
      XCTAssertTrue(purchase.waitForExistence(timeout: 15))
      let scroll = app.scrollViews.firstMatch
      XCTAssertTrue(scroll.exists)
      for _ in 0..<3 { scroll.swipeUp() }
      let feedback = state == "running"
        ? app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "正在恢复购买")).firstMatch
        : app.staticTexts["subscription.restore.feedback"]
      XCTAssertTrue(feedback.exists)
      XCTAssertGreaterThan(feedback.frame.height, 0)
      XCTAssertLessThanOrEqual(feedback.frame.maxY, purchase.frame.minY)
      attach(app, name: "restore-" + state + "-scrolled-feedback")
      app.terminate()
    }
  }

  @MainActor func testExpiredBackupOfferReturnsToTheSameHub() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "app.backupduck.catalog")
    app.launchArguments = ["-scenario", "hub.subscription-expired", "-capture",
      "-appearance", "light", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let entry = app.buttons["subscription.backup.continue"]
    XCTAssertTrue(entry.waitForExistence(timeout: 15))
    let earlier = app.descendants(matching: .any).matching(identifier: "hub.earlier_summary").firstMatch
    XCTAssertTrue(earlier.exists)
    let originalFrame = earlier.frame
    XCTAssertFalse(app.buttons["暂停"].exists)
    XCTAssertFalse(app.buttons["继续"].exists)
    XCTAssertFalse(app.buttons["开始备份"].exists)
    attach(app, name: "backup-expired-before")
    entry.tap()
    let purchase = app.buttons["subscription.purchase"]
    XCTAssertTrue(purchase.waitForExistence(timeout: 10))
    XCTAssertTrue(purchase.isHittable)
    attach(app, name: "backup-expired-offer")
    app.buttons["sheet.close"].tap()
    XCTAssertTrue(entry.isHittable)
    XCTAssertEqual(earlier.frame.minY, originalFrame.minY, accuracy: 1)
    XCTAssertEqual(earlier.frame.height, originalFrame.height, accuracy: 1)
    attach(app, name: "backup-expired-after-dismiss")
  }

  @MainActor func testNonStoreChannelsKeepBackupAndHideProEntries() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "app.backupduck.catalog")
    for channel in ["testflight", "direct"] {
      app.launchArguments = ["-scenario", "hub.subscription-expired-" + channel, "-capture",
        "-appearance", "light", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 15))
      XCTAssertFalse(app.buttons["subscription.backup.continue"].exists)
      attach(app, name: "backup-" + channel + "-normal")
      app.tabBars.buttons["设置"].tap()
      XCTAssertTrue(app.buttons["settings.auto_backup"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["subscription.settings.entry"].exists)
      attach(app, name: "settings-" + channel + "-no-pro")
      app.terminate()
    }
  }

  @MainActor private func attach(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
}
