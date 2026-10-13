import XCTest

@testable import BackupDuck

final class CalendarGridTests: XCTestCase {
  func testCalendarHierarchyKeepsEveryMemberAndCoverWithinItsPeriod() {
    let calendar = Calendar(identifier: .gregorian)
    let assets = (0..<120).map { i in
      CalendarGridAsset(
        id: "asset-\(i)",
        date: calendar.date(
          from: DateComponents(year: 2023 + i / 60, month: 1 + i % 60 / 10, day: 1 + i % 10 / 2)),
        aspect: 1.5)
    }
    for level in [CalendarGridLevel.years, .months, .all] {
      let g = CalendarGridGeometry(
        assets: assets, level: level, width: 390, columns: 5, originalAspect: false)
      XCTAssertEqual(g.tiles.flatMap { Array($0.members) }, Array(assets.indices))
      XCTAssertTrue(g.tiles.allSatisfy { $0.members.contains($0.asset) })
      XCTAssertTrue(g.tiles.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= 391 })
      for y in stride(from: 0.0, to: Double(g.height), by: 500) {
        let viewport = CGRect(x: 0, y: y, width: 390, height: 500)
        let range = g.visible(in: viewport)
        for i in g.tiles.indices where g.tiles[i].frame.intersects(viewport) {
          XCTAssertTrue(
            range.contains(i), "A tall hero tile must remain visible alongside shorter mosaic tiles"
          )
        }
      }
    }
  }
  func testDensityChangesKeepIdentityAndOriginalAspectDoesNotChangeMembership() {
    let assets = (0..<900).map {
      CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: $0 % 2 == 0 ? 0.7 : 1.8)
    }
    for columns in [1, 3, 5, 10, 20, 30] {
      for aspect in [false, true] {
        let g = CalendarGridGeometry(
          assets: assets, level: .all, width: 390, columns: columns, originalAspect: aspect)
        XCTAssertEqual(g.tiles.map(\.id), assets.map(\.id))
        XCTAssertEqual(g.tiles.map(\.members.lowerBound), Array(assets.indices))
        XCTAssertTrue(g.height > 0)
      }
    }
  }
  func testAnchoredColumnsRetainEveryAssetAndBoundHorizontalTravel() {
    let assets = (0..<1200).map { CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: 1) }
    let anchor = 609
    let width: CGFloat = 402
    let source = CalendarGridGeometry(
      assets: assets, level: .all, width: width, columns: 3, originalAspect: false)
    let point = source.tiles[anchor].frame.midX
    let side = (width - 8) / 5
    let column = Int(round((point - side * 0.5) / (side + 2)))
    let leading = (column - anchor % 5 + 5) % 5
    let destination = CalendarGridGeometry(
      assets: assets, level: .all, width: width, columns: 5, originalAspect: false,
      leadingSlots: leading)
    XCTAssertEqual(destination.tiles.map(\.id), assets.map(\.id))
    XCTAssertLessThanOrEqual(abs(destination.tiles[anchor].frame.midX - point), side * 0.5 + 2)
    XCTAssertNotEqual(
      CalendarGridController.geometryKey(.all, width: width, columns: 5, aspect: false),
      CalendarGridController.geometryKey(
        .all, width: width, columns: 5, aspect: false, leading: leading))
  }

}
