import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class SparseGridGeometryTests: XCTestCase {
  func testSparseStageFinalPoseWithinDisplayPixelAtEveryDensity() async throws {
    var comparedPoses = 0
    for count in [1, 2, 5, 12] {
      let grid = CalendarGridController()
      grid.requestImage = { item, _, done in done(SampleImages.cgImage(for: item.id).map { UIImage(cgImage: $0) }, false); return {} }
      grid.requestUncroppedImage = grid.requestImage
      grid.replaceAssets((0..<count).map { CalendarGridAsset(id: "catalog-library-\($0)", date: Scenario.fixtureNow, aspect: 1) })
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let window = UIWindow(windowScene: scene)
      window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
      window.rootViewController = CalendarNavigationController(rootViewController: grid)
      window.makeKeyAndVisible()
      try? await Task.sleep(for: .milliseconds(100))
      grid.loadViewIfNeeded(); grid.view.frame = window.bounds
      grid.view.setNeedsLayout(); grid.view.layoutIfNeeded(); grid.rebuildIfNeeded()
      XCTAssertEqual(grid.layout.geometry.tiles.count, count, "The native fixture must lay out its photos")
      for columns in grid.columnStops {
        grid.density(columns: columns, at: 0)
        guard let stage = grid.stage, let target = grid.pinchTrack.target,
          let face = stage.faces[grid.columnStops[target]] else { continue }
        comparedPoses += 1
        stage.pause()
        stage.show(columns, animated: false)
        stage.pitch = face.pitch
        stage.focus = CGPoint(x: face.focus.x, y: face.focus.y - grid.pinchTrack.finalOffset)
        stage.layoutAll()
        var frames: [String: CGRect] = [:]
        for (key, tile) in face.tiles where key.column >= 0 && key.column < face.columns {
          if let id = tile.photo.name { frames[id] = tile.convert(tile.bounds, to: stage.layer) }
        }
        XCTAssertFalse(frames.isEmpty, "The live stage must expose rendered tiles")
        grid.completeStage()
        grid.view.layoutIfNeeded()
        for tile in grid.layout.geometry.tiles {
          guard let rendered = frames[tile.id] else { continue }
          let settled = tile.frame.offsetBy(dx: 0, dy: -grid.grid.contentOffset.y)
          XCTAssertEqual(rendered.minX, settled.minX, accuracy: 1 / 3)
          XCTAssertEqual(rendered.minY, settled.minY, accuracy: 1 / 3)
          XCTAssertEqual(rendered.width, settled.width, accuracy: 1 / 3)
          XCTAssertEqual(rendered.height, settled.height, accuracy: 1 / 3)
        }
        let insets = grid.grid.adjustedContentInset
        if grid.layout.geometry.height < grid.grid.bounds.height - insets.top - insets.bottom {
          XCTAssertEqual(grid.grid.contentOffset.y, -insets.top, accuracy: 1 / grid.traitCollection.displayScale)
        }
      }
      grid.stopMotion(); window.isHidden = true
    }
    XCTAssertEqual(comparedPoses, 20)
  }
}
