import XCTest
import Photos

@testable import BackupDuck

final class CalendarGridTests: XCTestCase {

  private func membershipRows(_ count: Int) -> [CalendarGridAsset] {
    (0..<count).map { CalendarGridAsset(id: "member-\($0)", date: nil, aspect: 1) }
  }

  func testMembershipPlanBudgetsActualMovesAndPreservesSourceRevisions() throws {
    let old = membershipRows(120)
    let added = (0..<3).map { CalendarGridAsset(id: "new-\($0)", date: nil, aspect: 1) }
    let prepend = try XCTUnwrap(CalendarGridMembershipChange(old: old, new: added + old))
    XCTAssertEqual(prepend.inserted, [0, 1, 2])
    XCTAssertTrue(prepend.moves.isEmpty, "Shifted indices are not individual move operations")
    XCTAssertEqual(prepend.changeCount, 3)
    var reordered = old
    reordered.insert(reordered.remove(at: 75), at: 30)
    let move = try XCTUnwrap(CalendarGridMembershipChange(old: old, new: reordered))
    XCTAssertEqual(move.moves.count, 1)
    XCTAssertEqual(move.moves.first?.from, 75)
    XCTAssertEqual(move.moves.first?.to, 30)
    var revised = old
    revised[42].revision = 2
    let metadata = try XCTUnwrap(CalendarGridMembershipChange(old: old, new: revised))
    XCTAssertEqual(metadata.changeCount, 0)
    XCTAssertEqual(metadata.changedIDs, ["member-42"])
    let reversed = try XCTUnwrap(CalendarGridMembershipChange(old: old, new: Array(old.reversed())))
    XCTAssertGreaterThan(reversed.changeCount, 64, "A large reorder cannot bypass the animation budget")
    XCTAssertNil(CalendarGridMembershipChange(old: old, new: old + [old[0]]))
  }

  func testMembershipLayoutResolvesBeforeAndAfterFramesByIdentity() throws {
    let old = membershipRows(12)
    var values = old
    values.remove(at: 4)
    values.insert(CalendarGridAsset(id: "inserted", date: nil, aspect: 1), at: 2)
    let before = CalendarGridGeometry(assets: old, level: .all, width: 402, columns: 3, originalAspect: false)
    let after = CalendarGridGeometry(assets: values, level: .all, width: 402, columns: 3, originalAspect: false)
    let layout = CalendarGridLayout()
    let target = CGPoint(x: 0, y: 270)
    layout.beginMembershipUpdate(from: before, to: after, targetOffset: target)
    layout.geometry = after
    let moved = try XCTUnwrap(values.firstIndex { $0.id == "member-2" })
    XCTAssertEqual(layout.initialLayoutAttributesForAppearingItem(at: IndexPath(item: moved, section: 0))?.frame,
      before.tiles[2].frame)
    XCTAssertEqual(layout.finalLayoutAttributesForDisappearingItem(at: IndexPath(item: 2, section: 0))?.frame,
      after.tiles[moved].frame)
    XCTAssertEqual(layout.initialLayoutAttributesForAppearingItem(at: IndexPath(item: 2, section: 0))?.alpha, 0)
    XCTAssertEqual(layout.finalLayoutAttributesForDisappearingItem(at: IndexPath(item: 4, section: 0))?.alpha, 0)
    XCTAssertEqual(layout.targetContentOffset(forProposedContentOffset: .zero), target)
    layout.finishMembershipUpdate()
  }

  func testMembershipDeletedAnchorChoosesNearestVisibleSurvivor() throws {
    let old = membershipRows(120)
    let after = old.filter { $0.id != "member-60" }
    let change = try XCTUnwrap(CalendarGridMembershipChange(old: old, new: after))
    XCTAssertEqual(change.survivingAnchor(from: "member-60", preferredIDs: ["member-59", "member-61"]), "member-61")
    XCTAssertEqual(change.survivingAnchor(from: "member-60", preferredIDs: ["member-57"]), "member-57")
  }

  @MainActor private func membershipWindow(_ count: Int) async throws -> (UIWindow, CalendarGridController, Bool) {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let animationsWereEnabled = UIView.areAnimationsEnabled
    // XCTest disables UIView animation around ordinary unit tests. These tests
    // exercise the native update lifecycle, and restore that harness setting.
    UIView.setAnimationsEnabled(true)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    let controller = CalendarGridController()
    controller.columns = 3; controller.assets = membershipRows(count)
    controller.requestImage = { _, _, done in
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { context in
        UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
      }
      done(image, false); return {}
    }
    // Install the production status-bar owner before appearance, so its native
    // navigation child never reparents the window in the middle of the update.
    controller.prefetchImage = { _, _, _ in {} }
    window.rootViewController = MediaStatusBarRootController(
      content: CalendarNavigationController(rootViewController: controller))
    window.makeKeyAndVisible(); window.layoutIfNeeded(); controller.view.layoutIfNeeded()
    // Window appearance may hold UIKit's animations-disabled scope across the
    // initial run-loop turn. Wait for the real native appearance handoff.
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    repeat {
      try await Task.sleep(for: .milliseconds(20))
      if ContinuousClock.now >= deadline { XCTFail("Native membership fixture did not appear"); break }
    } while !controller.active || controller.transitionCoordinator != nil
    UIView.setAnimationsEnabled(true)
    XCTAssertTrue(UIView.areAnimationsEnabled)
    XCTAssertFalse(UIAccessibility.isReduceMotionEnabled)
    XCTAssertTrue(controller.view.window === window)
    return (window, controller, animationsWereEnabled)
  }

  @MainActor private func waitForMembership(_ controller: CalendarGridController, ids: [String]) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while controller.membershipUpdating || controller.assets.map(\.id) != ids || controller.pendingAssets != nil {
      if ContinuousClock.now >= deadline { XCTFail("Native membership update did not complete"); return }
      try await Task.sleep(for: .milliseconds(20))
    }
    controller.grid.layoutIfNeeded()
  }

  @MainActor func testNativeMembershipCoalescesInsertDeleteAndKeepsMidLibraryAnchor() async throws {
    let (window, c, animationsWereEnabled) = try await membershipWindow(120)
    defer { window.isHidden = true; window.rootViewController = nil; UIView.setAnimationsEnabled(animationsWereEnabled) }
    c.place(2_000)
    let anchor = try XCTUnwrap(c.browsingAnchor())
    let old = c.assets
    let first = [CalendarGridAsset(id: "new-a", date: nil, aspect: 1)] + old
    c.replaceAssets(first)
    XCTAssertTrue(c.membershipUpdating)
    let latest = [CalendarGridAsset(id: "new-b", date: nil, aspect: 1)] + first
    c.replaceAssets(latest)
    XCTAssertEqual(c.pendingAssets, latest)
    try await waitForMembership(c, ids: latest.map(\.id))
    let tile = try XCTUnwrap(c.layout.geometry.tiles.first { $0.id == anchor.id })
    XCTAssertEqual(tile.frame.minY - c.grid.contentOffset.y, anchor.screenY, accuracy: 1)
    let deleting = c.assets.filter { $0.id != anchor.id }
    c.replaceAssets(deleting)
    XCTAssertTrue(c.membershipUpdating)
    try await waitForMembership(c, ids: deleting.map(\.id))
    XCTAssertEqual(c.grid.numberOfItems(inSection: 0), deleting.count)
    for case let cell as CalendarGridCell in c.grid.visibleCells {
      let path = try XCTUnwrap(c.grid.indexPath(for: cell))
      XCTAssertEqual(cell.assetID, c.assets[path.item].id)
      XCTAssertEqual(cell.coverAsset, path.item)
      XCTAssertNotNil(cell.image.image)
    }
  }

  @MainActor func testNativeMembershipNewestEdgeAndLargeBatchFallback() async throws {
    let (window, c, animationsWereEnabled) = try await membershipWindow(120)
    defer { window.isHidden = true; window.rootViewController = nil; UIView.setAnimationsEnabled(animationsWereEnabled) }
    c.scrollToLatest()
    let added = c.assets + [CalendarGridAsset(id: "newest", date: nil, aspect: 1)]
    c.replaceAssets(added)
    XCTAssertTrue(c.membershipUpdating)
    try await waitForMembership(c, ids: added.map(\.id))
    XCTAssertEqual(c.grid.contentOffset.y, c.clampedOffset(.greatestFiniteMagnitude), accuracy: 1)
    let many = c.assets + (0..<1000).map { CalendarGridAsset(id: "large-\($0)", date: nil, aspect: 1) }
    c.replaceAssets(many)
    XCTAssertFalse(c.membershipUpdating)
    XCTAssertEqual(c.grid.numberOfItems(inSection: 0), many.count)
  }

  @MainActor func testNativeMembershipDefersWhileViewerAndAcceptsPendingContextRestore() async throws {
    let (window, c, animationsWereEnabled) = try await membershipWindow(120)
    defer { window.isHidden = true; window.rootViewController = nil; UIView.setAnimationsEnabled(animationsWereEnabled) }
    c.place(2_000)
    let old = c.assets
    c.setPreviewHidden(old[50].id)
    let first = old + [CalendarGridAsset(id: "later", date: nil, aspect: 1)]
    c.replaceAssets(first)
    XCTAssertEqual(c.assets, old)
    XCTAssertEqual(c.pendingAssets, first)
    c.setPreviewHidden(nil)
    try await waitForMembership(c, ids: first.map(\.id))
    c.replaceAssets(first + [CalendarGridAsset(id: "second", date: nil, aspect: 1)])
    XCTAssertTrue(c.membershipUpdating)
    let context = Array(old[30..<90])
    let anchor = LibraryBrowseAnchor(id: "member-50", screenY: 240, leadingSlots: 0)
    c.replaceAssets(context, newView: true, anchor: anchor)
    try await waitForMembership(c, ids: context.map(\.id))
    let tile = try XCTUnwrap(c.layout.geometry.tiles.first { $0.id == anchor.id })
    XCTAssertEqual(tile.frame.minY - c.grid.contentOffset.y, anchor.screenY, accuracy: 1)
  }

  @MainActor func testNativeMembershipMetadataKeepsPixelsAndRejectsLateRevision() async throws {
    let (window, c, animationsWereEnabled) = try await membershipWindow(120)
    defer { window.isHidden = true; window.rootViewController = nil; UIView.setAnimationsEnabled(animationsWereEnabled) }
    c.place(2_000)
    let cell = try XCTUnwrap(c.grid.visibleCells.compactMap { $0 as? CalendarGridCell }.first)
    let id = cell.assetID
    let index = try XCTUnwrap(c.assets.firstIndex { $0.id == id })
    let image = try XCTUnwrap(cell.image.image)
    var requests = 0
    var deliveries: [Int64: (UIImage?, Bool) -> Void] = [:]
    c.requestImage = { asset, _, done in
      requests += 1
      if asset.id == id { deliveries[asset.revision] = done }
      return {}
    }
    var metadata = c.assets
    metadata[index].videoDuration = "0:12"
    c.replaceAssets(metadata)
    try await waitForMembership(c, ids: metadata.map(\.id))
    XCTAssertTrue(cell.image.image === image)
    XCTAssertEqual(requests, 0, "A duration observation must not restart the photo rendition")
    var first = metadata; first[index].revision = 1
    c.replaceAssets(first)
    try await waitForMembership(c, ids: first.map(\.id))
    var second = first; second[index].revision = 2
    c.replaceAssets(second)
    try await waitForMembership(c, ids: second.map(\.id))
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    func bitmap(_ color: UIColor) -> UIImage {
      UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { context in
        color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
      }
    }
    let current = bitmap(.systemGreen), obsolete = bitmap(.systemRed)
    try XCTUnwrap(deliveries[2])(current, false)
    try XCTUnwrap(deliveries[1])(obsolete, false)
    XCTAssertTrue(cell.image.image === current, "An obsolete file revision cannot overwrite the new picture")
  }

  @MainActor func testNativeMembershipPermutationWithFixedMiddleRetainsNativeIdentity() async throws {
    let (window, c, animationsWereEnabled) = try await membershipWindow(9)
    defer { window.isHidden = true; window.rootViewController = nil; UIView.setAnimationsEnabled(animationsWereEnabled) }
    let values = Array(c.assets.reversed())
    c.replaceAssets(values)
    XCTAssertTrue(c.membershipUpdating)
    try await waitForMembership(c, ids: values.map(\.id))
    XCTAssertEqual(c.grid.numberOfItems(inSection: 0), values.count)
    for case let cell as CalendarGridCell in c.grid.visibleCells {
      let path = try XCTUnwrap(c.grid.indexPath(for: cell))
      XCTAssertEqual(cell.assetID, values[path.item].id)
      XCTAssertEqual(cell.coverAsset, path.item)
    }
  }

  func testLargeMembershipPlanReconstructsMixedSnapshotsAndPermutations() throws {
    var rows = membershipRows(60_000)
    var random: UInt64 = 0xBACC_D0C0
    func position(_ count: Int) -> Int {
      random = random &* 6_364_136_223_846_793_005 &+ 1
      return Int((random >> 32) % UInt64(count))
    }
    for round in 0..<24 {
      var next = rows
      for _ in 0..<(round % 5 + 1) { next.remove(at: position(next.count)) }
      for item in 0..<(round % 7 + 1) {
        next.insert(CalendarGridAsset(id: "stress-\(round)-\(item)", date: nil, aspect: 1),
          at: position(next.count + 1))
      }
      for _ in 0..<(round % 5 + 1) {
        let moved = next.remove(at: position(next.count))
        next.insert(moved, at: position(next.count + 1))
      }
      next[position(next.count)].revision += 1
      if round % 8 == 7 { next.reverse() }
      let change = try XCTUnwrap(CalendarGridMembershipChange(old: rows, new: next))
      XCTAssertEqual(change.oldIndices.count, rows.count)
      XCTAssertEqual(change.newIndices.count, next.count)
      XCTAssertEqual(rows.count - change.deleted.count + change.inserted.count, next.count)
      XCTAssertEqual(Set(change.moves.map(\.from)).count, change.moves.count)
      XCTAssertEqual(Set(change.moves.map(\.to)).count, change.moves.count)
      let removed = Set(change.deleted).union(change.moves.map(\.from))
      let destinations = Set(change.inserted).union(change.moves.map(\.to))
      XCTAssertEqual(removed.count, change.deleted.count + change.moves.count)
      XCTAssertEqual(destinations.count, change.inserted.count + change.moves.count)
      var reconstructed = [String?](repeating: nil, count: next.count)
      for inserted in change.inserted { reconstructed[inserted] = next[inserted].id }
      for move in change.moves { reconstructed[move.to] = rows[move.from].id }
      let remaining = rows.indices.filter { !removed.contains($0) }
      let unoccupied = next.indices.filter { !destinations.contains($0) }
      XCTAssertEqual(remaining.count, unoccupied.count)
      for (source, destination) in zip(remaining, unoccupied) { reconstructed[destination] = rows[source].id }
      XCTAssertTrue(reconstructed == next.map { Optional($0.id) }, "Every item must map bijectively in round \(round)")
      if round % 8 == 7 { XCTAssertGreaterThan(change.changeCount, 64) }
      rows = next
    }
  }

  @MainActor private func assertLargeMembership(_ c: CalendarGridController, equals values: [CalendarGridAsset]) throws {
    c.grid.layoutIfNeeded()
    XCTAssertEqual(c.grid.numberOfItems(inSection: 0), values.count)
    XCTAssertTrue(c.assets == values)
    XCTAssertTrue(c.layout.geometry.tiles.map(\.id) == values.map(\.id))
    XCTAssertLessThan(c.grid.visibleCells.count, 120, "A large library must retain native cell virtualization")
    for case let cell as CalendarGridCell in c.grid.visibleCells {
      let path = try XCTUnwrap(c.grid.indexPath(for: cell))
      XCTAssertTrue(values.indices.contains(path.item))
      guard values.indices.contains(path.item) else { continue }
      XCTAssertEqual(cell.assetID, values[path.item].id)
      XCTAssertEqual(cell.coverAsset, path.item)
      XCTAssertEqual(cell.assetRevision, values[path.item].revision)
      XCTAssertNotNil(cell.image.image)
    }
  }

  @MainActor func testLargeNativeMembershipRepeatedMixedBatchesAndLatestCoalescing() async throws {
    let (window, c, animationsWereEnabled) = try await membershipWindow(60_000)
    defer { window.isHidden = true; window.rootViewController = nil; UIView.setAnimationsEnabled(animationsWereEnabled) }
    c.place(c.grid.contentSize.height / 2)
    for round in 0..<4 {
      let old = c.assets
      let anchor = try XCTUnwrap(c.browsingAnchor())
      let focus = try XCTUnwrap(old.firstIndex { $0.id == anchor.id })
      let visible = c.layout.geometry.visible(in: c.grid.bounds).map { c.layout.geometry.tiles[$0].id }
      var first = old
      first.remove(at: focus)
      first.insert(CalendarGridAsset(id: "native-first-\(round)", date: nil, aspect: 1), at: focus - 3)
      first.insert(first.remove(at: focus + 9), at: focus - 6)
      let plan = try XCTUnwrap(CalendarGridMembershipChange(old: old, new: first))
      let surviving = try XCTUnwrap(plan.survivingAnchor(from: anchor.id, preferredIDs: visible))
      let retainedFrame = try XCTUnwrap(c.layout.geometry.tiles.first { $0.id == surviving }).frame
      let retainedY = retainedFrame.minY - c.grid.contentOffset.y
      c.replaceAssets(first)
      XCTAssertTrue(c.membershipUpdating, "Round \(round) must exercise an actual animated native batch")
      var intermediate = first
      intermediate.insert(CalendarGridAsset(id: "native-intermediate-\(round)", date: nil, aspect: 1), at: focus + 6)
      c.replaceAssets(intermediate)
      var latest = first
      latest.insert(CalendarGridAsset(id: "native-latest-\(round)", date: nil, aspect: 1), at: focus - 5)
      latest.remove(at: focus + 12)
      latest.insert(latest.remove(at: focus + 18), at: focus - 9)
      c.replaceAssets(latest)
      XCTAssertTrue(c.pendingAssets == latest, "Only the latest waiting snapshot may survive")
      try await waitForMembership(c, ids: latest.map(\.id))
      try assertLargeMembership(c, equals: latest)
      let frame = try XCTUnwrap(c.layout.geometry.tiles.first { $0.id == surviving }).frame
      XCTAssertEqual(frame.minY - c.grid.contentOffset.y, retainedY, accuracy: 1,
        "Deleting the visible focus must preserve its surviving neighbour through the coalesced chain")
      XCTAssertFalse(c.assets.contains { $0.id == "native-intermediate-\(round)" })
    }
  }

  @MainActor func testLargeNativeMembershipAnimationBudgetBoundaries() async throws {
    let (window, c, animationsWereEnabled) = try await membershipWindow(60_000)
    defer { window.isHidden = true; window.rootViewController = nil; UIView.setAnimationsEnabled(animationsWereEnabled) }
    c.place(c.grid.contentSize.height / 2)
    for count in [64, 65, 1_000] {
      let anchor = try XCTUnwrap(c.browsingAnchor())
      let focus = try XCTUnwrap(c.assets.firstIndex { $0.id == anchor.id })
      var next = c.assets
      next.insert(contentsOf: (0..<count).map {
        CalendarGridAsset(id: "native-budget-\(count)-\($0)", date: nil, aspect: 1)
      }, at: focus)
      let plan = try XCTUnwrap(CalendarGridMembershipChange(old: c.assets, new: next))
      XCTAssertEqual(plan.changeCount, count)
      c.replaceAssets(next)
      XCTAssertEqual(c.membershipUpdating, count == 64, "Only the bounded batch may animate")
      try await waitForMembership(c, ids: next.map(\.id))
      try assertLargeMembership(c, equals: next)
      let frame = try XCTUnwrap(c.layout.geometry.tiles.first { $0.id == anchor.id }).frame
      XCTAssertEqual(frame.minY - c.grid.contentOffset.y, anchor.screenY, accuracy: 1)
    }
  }

  @MainActor private func preparedOverview(count: Int, lookup: @escaping (Int) -> CGImage?) async -> CalendarOverviewPixels {
    let pixels = CalendarOverviewPixels(count: count)
    let ready = expectation(description: "Background overview pixels")
    pixels.didFinish = { _ in ready.fulfill() }
    pixels.prepare(lookup: lookup)
    await fulfillment(of: [ready], timeout: 30)
    pixels.didFinish = nil
    XCTAssertLessThanOrEqual(pixels.byteCost, CalendarOverviewPixels.byteLimit)
    return pixels
  }

  func testOverviewArchiveMatchesIdentityAndRejectsGeometryAndCorruption() throws {
    var assets = (0..<3).map { CalendarGridAsset(id: "archive-\($0)", date: nil, aspect: 1) }
    let chunk = CalendarOverviewPixels.Chunk(bytes: Data(repeating: 1, count: 256) + Data(repeating: 2, count: 256) + Data(repeating: 3, count: 256), ready: [true, false, true])
    let data = try XCTUnwrap(CalendarOverviewPixels.encodeArchive(assets, count: 3, side: 8, first: 0, chunks: [0: chunk]))
    let decoded = try XCTUnwrap(CalendarOverviewPixels.decodeArchive(data, assets: assets, count: 3, side: 8, first: 0))
    XCTAssertEqual(decoded[0]?.bytes, chunk.bytes)
    XCTAssertEqual(decoded[0]?.ready, chunk.ready)
    assets.swapAt(0, 1)
    let reordered = try XCTUnwrap(CalendarOverviewPixels.decodeArchive(data, assets: assets, count: 3, side: 8, first: 0)?[0])
    XCTAssertEqual(reordered.ready, [false, true, true])
    XCTAssertEqual(reordered.bytes[256], 1)
    assets.swapAt(0, 1); assets[0].revision = 1
    let edited = try XCTUnwrap(CalendarOverviewPixels.decodeArchive(data, assets: assets, count: 3, side: 8, first: 0)?[0])
    XCTAssertEqual(edited.ready, [false, false, true])
    assets.remove(at: 0)
    assets.append(CalendarGridAsset(id: "new", date: nil, aspect: 1))
    let changed = try XCTUnwrap(CalendarOverviewPixels.decodeArchive(data, assets: assets, count: 3, side: 8, first: 0)?[0])
    XCTAssertEqual(changed.ready, [false, true, false])
    XCTAssertEqual(changed.bytes[256], 3)
    assets = (0..<3).map { CalendarGridAsset(id: "archive-\($0)", date: nil, aspect: 1) }
    assets[0].revision = 0
    XCTAssertNil(CalendarOverviewPixels.decodeArchive(data, assets: assets, count: 3, side: 4, first: 0))
    let oversized = Array(repeating: assets[0], count: 200_001)
    XCTAssertNil(CalendarOverviewPixels.decodeArchive(data, assets: oversized, count: oversized.count, side: 8, first: 0))
    XCTAssertNil(CalendarOverviewPixels.encodeArchive(oversized, count: oversized.count, side: 8, first: 0, chunks: [0: chunk]))
    XCTAssertNil(CalendarOverviewPixels.decodeArchive(data.dropLast(), assets: assets, count: 3, side: 8, first: 0))
    var corrupt = data; corrupt[corrupt.count / 2] ^= 1
    XCTAssertNil(CalendarOverviewPixels.decodeArchive(corrupt, assets: assets, count: 3, side: 8, first: 0))
  }

  func testOverviewCacheAccountsAndRejectsOldEpochs() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "overview-cache-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let abandoned = directory.appendingPathComponent("previous-process.overviewtmp")
    try Data(repeating: 7, count: 4096).write(to: abandoned)
    let disk = ThumbnailDiskCache(directory: directory, defaults: defaults)
    let initialUsage = await disk.usage()
    XCTAssertEqual(initialUsage, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
    let (_, epoch) = await disk.readOverview()
    let data = Data(repeating: 5, count: 4096)
    await disk.storeOverview(data, generation: epoch, valid: { true })
    let (read, _) = await disk.readOverview()
    XCTAssertEqual(read, data)
    let usage = await disk.usage(); XCTAssertEqual(usage, data.count)
    _ = await disk.removeAll()
    await disk.storeOverview(data, generation: epoch, valid: { true })
    let (cleared, newEpoch) = await disk.readOverview()
    XCTAssertNil(cleared)
    await disk.setBudget(64)
    await disk.storeOverview(data, generation: newEpoch, valid: { true })
    let (afterBudget, currentEpoch) = await disk.readOverview()
    XCTAssertNil(afterBudget)
    await disk.storeOverview(data, generation: currentEpoch, valid: { false })
    let (cancelled, _) = await disk.readOverview()
    XCTAssertNil(cancelled)
  }

  func testOverviewClearWinsAgainstConcurrentWrite() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "overview-race-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
    let disk = ThumbnailDiskCache(directory: directory, defaults: defaults)
    let (_, epoch) = await disk.readOverview()
    let data = Data(repeating: 9, count: 16 * 1024 * 1024)
    let writer = Task { await disk.storeOverview(data, generation: epoch, valid: { true }) }
    _ = await disk.removeAll()
    await writer.value
    let (loaded, _) = await disk.readOverview()
    let usage = await disk.usage()
    XCTAssertNil(loaded)
    XCTAssertEqual(usage, 0)
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertFalse(files.contains { $0.hasSuffix(".overviewtmp") })
  }

  func testLargeOverviewArchiveReusesPixelsAfterLibraryChange() throws {
    let count = 54_714, side = 8, pixelBytes = side * side * 4
    let assets = (0..<count).map { CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: 1) }
    var chunks: [Int: CalendarOverviewPixels.Chunk] = [:]
    for batch in 0..<((count + 255) / 256) {
      let entries = min(256, count - batch * 256)
      chunks[batch] = CalendarOverviewPixels.Chunk(bytes: Data(repeating: UInt8(batch % 251 + 1), count: entries * pixelBytes),
        ready: Array(repeating: true, count: entries))
    }
    let start = CFAbsoluteTimeGetCurrent()
    let archive = try XCTUnwrap(CalendarOverviewPixels.encodeArchive(assets, count: count, side: side, first: 0, chunks: chunks))
    var changed = assets
    changed.removeFirst(); changed.append(CalendarGridAsset(id: "new-asset", date: nil, aspect: 1))
    let readStart = CFAbsoluteTimeGetCurrent()
    let decoded = try XCTUnwrap(CalendarOverviewPixels.decodeArchive(archive, assets: changed, count: count, side: side, first: 0))
    let ready = decoded.values.reduce(0) { $0 + $1.ready.filter { $0 }.count }
    XCTAssertEqual(ready, count - 1)
    XCTAssertEqual(decoded[0]?.bytes[0], 1)
    XCTAssertFalse(try XCTUnwrap(decoded[(count - 1) / 256]).ready[(count - 1) % 256])
    print("Overview archive synthetic bytes=\(archive.count) encode=\(readStart - start) decode-remap=\(CFAbsoluteTimeGetCurrent() - readStart)")
  }

  @MainActor func testOverviewArchivePublishesMatchesBeforePreparingMissingItems() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "overview-load-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
    let disk = ThumbnailDiskCache(directory: directory, defaults: defaults)
    let old = (0..<3).map { CalendarGridAsset(id: "item-\($0)", date: nil, aspect: 1) }
    let pixels = CalendarOverviewPixels(count: 3)
    let size = pixels.side * pixels.side * 4
    let chunk = CalendarOverviewPixels.Chunk(bytes: Data(repeating: 17, count: size * 3), ready: [true, true, true])
    let data = try XCTUnwrap(CalendarOverviewPixels.encodeArchive(old, count: 3, side: pixels.side, first: 0, chunks: [0: chunk]))
    let (_, epoch) = await disk.readOverview()
    await disk.storeOverview(data, generation: epoch, valid: { true })
    var current = old
    current.removeFirst(); current.append(CalendarGridAsset(id: "new", date: nil, aspect: 1))
    let published = expectation(description: "Matching cached pixels published")
    let finished = expectation(description: "Missing entry prepared")
    pixels.didPrepare = { _ in
      if pixels.preparedCount == 2 { published.fulfill() }
    }
    pixels.didFinish = { _ in finished.fulfill() }
    pixels.prepare(assets: current, disk: disk) { index in
      XCTAssertEqual(index, 2, "Only the new asset needs its source image")
      return nil
    }
    await fulfillment(of: [published, finished], timeout: 10)
    XCTAssertTrue(pixels.contains(0)); XCTAssertTrue(pixels.contains(1)); XCTAssertFalse(pixels.contains(2))
  }

  @MainActor func testColdOverviewPreparationNeverRunsOnScrollThreadAndRetriesMisses() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
      UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    }.cgImage!
    let assets = (0..<3000).map { CalendarGridAsset(id: "cold-\($0)", date: nil, aspect: 1) }
    let canvas = CalendarDenseCanvas(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 31, originalAspect: false)
    canvas.reset(geometry, columns: 31, fill: true)
    let overview = CalendarOverviewPixels(count: assets.count)
    canvas.overviewPixels = overview
    let entered = expectation(description: "Cold read begins off main"), finished = expectation(description: "Background reads finish")
    let gate = DispatchSemaphore(value: 0)
    var first = true
    overview.didFinish = { _ in finished.fulfill() }
    overview.prepare { index in
      XCTAssertFalse(Thread.isMainThread)
      if first { first = false; entered.fulfill(); gate.wait() }
      return index.isMultiple(of: 2) ? image : nil
    }
    await fulfillment(of: [entered], timeout: 5)
    canvas.renderQueue.suspend()
    defer { canvas.stop(); canvas.renderQueue.resume() }
    canvas.tableLookup = { _ in
      XCTAssertFalse(Thread.isMainThread, "The scroll callback must never touch a disk-backed provider")
      return nil
    }
    canvas.update(visible: canvas.bounds, scale: 3)
    XCTAssertEqual(canvas.coverage(in: canvas.bounds), 0, "Unprepared pixels cannot be reported as displayed")
    gate.signal()
    await fulfillment(of: [finished], timeout: 5)
    canvas.update(visible: canvas.bounds, scale: 3)
    XCTAssertGreaterThan(canvas.coverage(in: canvas.bounds), 0.49)
    XCTAssertLessThan(canvas.coverage(in: canvas.bounds), 0.51)
    let retried = expectation(description: "Missing entries retry")
    overview.didFinish = { _ in retried.fulfill() }
    overview.prepare { index in
      XCTAssertFalse(index.isMultiple(of: 2), "Prepared immutable pixels survive a retry")
      return image
    }
    await fulfillment(of: [retried], timeout: 5)
    canvas.update(visible: canvas.bounds, scale: 3)
    XCTAssertEqual(canvas.coverage(in: canvas.bounds), 1)
  }

  @MainActor func testOverviewPixelBudgetAndControllerLifetime() async throws {
    for count in [1, 1000, 55552, 1_000_000, 10_000_000] {
      for budget in [4, 16].map({ $0 * 1024 * 1024 }) {
        let pixels = CalendarOverviewPixels(count: count, byteLimit: budget)
        XCTAssertLessThanOrEqual((count - pixels.firstAsset) * pixels.side * pixels.side * 4, budget)
      }
    }
    let controller = CalendarGridController()
    controller.prepareOverviewImage = { _ in nil }
    controller.replaceAssets((0..<55552).map { CalendarGridAsset(id: "lifetime-\($0)", date: nil, aspect: 1) })
    XCTAssertNil(controller.denseCanvas.overviewPixels, "A hidden controller must not start another whole-library pixel set")
    controller.viewDidAppear(false)
    let first = try? XCTUnwrap(controller.denseCanvas.overviewPixels)
    XCTAssertEqual(first?.side, 8)
    controller.viewDidDisappear(false)
    XCTAssertNil(controller.denseCanvas.overviewPixels)
    controller.didReceiveMemoryWarning()
    controller.viewDidAppear(false)
    XCTAssertEqual(controller.denseCanvas.overviewPixels?.side, 4)
    controller.viewDidDisappear(false)
  }

  @MainActor func testPreparedOverviewSurvivesTemporaryViewerAndMatchesRevision() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
      UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    }.cgImage!
    let controller = CalendarGridController()
    var assets = (0..<2000).map { CalendarGridAsset(id: "return-\($0)", date: nil, aspect: 1) }
    controller.prepareOverviewImage = { _ in image }
    controller.replaceAssets(assets)
    controller.viewDidAppear(false)
    let pixels = try XCTUnwrap(controller.denseCanvas.overviewPixels)
    let ready = expectation(description: "Prepared before viewer")
    pixels.didFinish = { _ in ready.fulfill() }
    await fulfillment(of: [ready], timeout: 5)
    controller.viewDidDisappear(false)
    XCTAssertNil(controller.denseCanvas.overviewPixels)
    controller.viewDidAppear(false)
    XCTAssertTrue(controller.denseCanvas.overviewPixels === pixels, "A temporary viewer must not discard already-prepared distant photos")
    XCTAssertEqual(pixels.preparedCount, assets.count)
    controller.viewDidDisappear(false)
    assets[0].revision = 2
    controller.replaceAssets(assets)
    controller.viewDidAppear(false)
    XCTAssertFalse(controller.denseCanvas.overviewPixels === pixels, "A changed revision must not reuse old photo identity")
    controller.viewDidDisappear(false)
  }

  @MainActor func testAspectFitOverviewKeepsVariableRowCentersAndPadding() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
      UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    }.cgImage!
    let columns = 15
    let assets = (0..<3000).map {
      CalendarGridAsset(id: "fit-\($0)", date: nil, aspect: ($0 / columns).isMultiple(of: 2) ? 0.6 : 2)
    }
    let canvas = CalendarDenseCanvas(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
    canvas.overrideUserInterfaceStyle = .light
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: columns, originalAspect: true)
    canvas.reset(geometry, columns: columns, fill: false)
    canvas.overviewPixels = await preparedOverview(count: assets.count) { _ in image }
    canvas.renderQueue.suspend()
    defer { canvas.stop(); canvas.renderQueue.resume() }
    canvas.update(visible: canvas.bounds, scale: 3)
    XCTAssertEqual(canvas.coverage(in: canvas.bounds), 1)
    let rendered = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
      UIColor.white.setFill(); context.fill(canvas.bounds); canvas.layer.render(in: context.cgContext)
    }.cgImage!
    func pixel(_ point: CGPoint) throws -> [UInt8] {
      let sample = try XCTUnwrap(rendered.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)))
      let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
        bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
      context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 3))
    }
    for index in [0, 15, 30, 45, 60] {
      let frame = geometry.tiles[index].frame
      let center = try pixel(CGPoint(x: frame.midX, y: frame.midY))
      XCTAssertGreaterThan(center[0], 240); XCTAssertLessThan(center[1], 15)
      let margin = try pixel(frame.height > frame.width
        ? CGPoint(x: frame.midX, y: frame.minY + 2) : CGPoint(x: frame.minX + 2, y: frame.midY))
      XCTAssertGreaterThan(margin[1], 220, "Aspect-fit padding must keep the row's background instead of stretching pixels")
    }
  }

  @MainActor func testDenseOutgoingFaceKeepsVariedVideoAndStateMarks() throws {
    let assets = (0..<55000).map { CalendarGridAsset(id: "varied-\($0)", date: nil, aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 5, originalAspect: false)
    let stage = CalendarZoomStage(frame: CGRect(x: 0, y: 0, width: 440, height: 956), columns: 31,
      pitch: 440 / 31, focus: CGPoint(x: 220, y: 478), displayScale: 3)
    stage.configureDecorations = { badges, index in
      badges.duration.text = String(format: "%d:%02d", index / 60, index % 60)
      badges.liveMark.image = index.isMultiple(of: 3) ? CalendarTileDecorations.Style.symbol("livephoto") : nil
      badges.backupState(index.isMultiple(of: 2) ? "sending" : "failed", visible: true)
    }
    let start = CACurrentMediaTime()
    let face = stage.addFace(columns: 5, geometry: geometry, focus: geometry.tiles[27500].frame.origin,
      pitch: CalendarGridGeometry.pitch(width: 440, columns: 5), opacity: 1)
    let elapsed = (CACurrentMediaTime() - start) * 1000
    let uniqueImages = Set(face.tiles.values.flatMap { $0.compactDecorations?.artwork.marks.map { ObjectIdentifier($0.0) } ?? [] })
    print("DEEP_GRID varied tiles=\(face.tiles.count) build_ms=\(elapsed) unique_mark_images=\(uniqueImages.count)")
    for (key, tile) in face.tiles {
      let index = key.row * 5 + key.column
      let compact = try XCTUnwrap(tile.compactDecorations)
      XCTAssertEqual(compact.artwork.state.duration, String(format: "%d:%02d", index / 60, index % 60))
      XCTAssertEqual(compact.artwork.state.live != nil, index.isMultiple(of: 3))
      XCTAssertEqual(compact.artwork.marks.count,
        1 + (compact.artwork.state.live == nil ? 0 : 1) + (compact.artwork.state.status == nil ? 0 : 1))
    }
    stage.stop()
  }

  @MainActor func testStageRequestsProjectedPixelsAndUpgradesOnlySurvivingTiles() throws {
    let assets = (0..<55000).map { CalendarGridAsset(id: "lod-\($0)", date: nil, aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 5, originalAspect: false)
    let stage = CalendarZoomStage(frame: CGRect(x: 0, y: 0, width: 440, height: 956), columns: 31,
      pitch: 440 / 31, focus: CGPoint(x: 220, y: 478), displayScale: 3)
    var requested: [CGFloat] = [], cancelled = 0
    stage.configureTile = { _, _, pixels in requested.append(pixels); return { cancelled += 1 } }
    let start = CACurrentMediaTime()
    let face = stage.addFace(columns: 5, geometry: geometry, focus: geometry.tiles[27500].frame.origin,
      pitch: CalendarGridGeometry.pitch(width: 440, columns: 5), opacity: 1)
    print("DEEP_GRID projected face tiles=\(face.tiles.count) build_ms=\((CACurrentMediaTime()-start)*1000) max_pixels=\(requested.max() ?? 0)")
    XCTAssertGreaterThan(face.tiles.count, 2000)
    XCTAssertTrue(requested.allSatisfy { $0 <= 64 }, "A tiny outgoing ordinary face must not request thousands of resting-size photos")
    let lowTierCount = requested.count
    stage.pitch = face.pitch; stage.layoutAll()
    XCTAssertLessThan(face.tiles.count, 100)
    XCTAssertTrue(face.tiles.values.allSatisfy { $0.requestedPixels >= 256 })
    XCTAssertLessThan(requested.count - lowTierCount, 100, "Only the surviving viewport upgrades its pixels")
    XCTAssertGreaterThan(cancelled, 2000)
    let afterUpgrade = requested.count
    stage.pitch *= 0.999; stage.layoutAll()
    XCTAssertEqual(requested.count, afterUpgrade, "Movement inside one rendition tier does not restart requests")
    stage.stop()
  }

  @MainActor func testDenseScrollShowsCachedPixelsBeforeRasterWorkStarts() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    }.cgImage!
    let overview = await preparedOverview(count: 55000) { _ in image }
    for columns in [15, 31] {
      let canvas = CalendarDenseCanvas(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
      let assets = (0..<55000).map { CalendarGridAsset(id: "cover-\($0)", date: nil, aspect: 1) }
      let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440,
        columns: columns, originalAspect: false, leadingSlots: columns / 2)
      canvas.reset(geometry, columns: columns, fill: true)
      canvas.overviewPixels = overview
      canvas.tableLookup = { _ in XCTAssertFalse(Thread.isMainThread); return image }
      canvas.renderQueue.suspend()
      defer { canvas.stop(); canvas.renderQueue.resume() }
      var timings: [Double] = []
      for fraction: CGFloat in [0, 0.8, 0.2, 0.6, 0.1] {
        let visible = canvas.bounds.offsetBy(dx: 0, dy: (geometry.height - canvas.bounds.height) * fraction)
        let start = CACurrentMediaTime()
        canvas.update(visible: visible, scale: 3)
        timings.append((CACurrentMediaTime() - start) * 1000)
        XCTAssertEqual(canvas.coverage(in: visible), 1, "Hot pixels must cover newly exposed rows before the worker can run")
        XCTAssertFalse(canvas.isReady(in: visible), "The temporary cover is distinct from the finished bitmap")
        let first = try XCTUnwrap(geometry.visible(in: visible).first { geometry.tiles[$0].frame.intersects(visible) })
        XCTAssertNotNil(canvas.displayedImage(first))
      }
      print("DEEP_GRID immediate covers columns=\(columns) update_ms=\(timings)")
    }
  }

  @MainActor func testDenseAtlasesKeepDistinctPixelsWithBoundedLayers() async throws {
    let color = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    let photos: [CGImage] = (0..<6000).map { index in
      let side = index.isMultiple(of: 2) ? 48 : 64
      let data = CFDataCreateMutable(nil, side * side * 4)!
      CFDataSetLength(data, side * side * 4)
      let bytes = CFDataGetMutableBytePtr(data)!
      for pixel in 0..<(side * side) {
        bytes[pixel * 4] = UInt8(index % 251)
        bytes[pixel * 4 + 1] = UInt8(index / 251)
        bytes[pixel * 4 + 2] = UInt8((index * 7) % 251)
        bytes[pixel * 4 + 3] = 0
      }
      return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
        space: color, bitmapInfo: info, provider: CGDataProvider(data: data)!, decode: nil,
        shouldInterpolate: true, intent: .defaultIntent)!
    }
    let overview = await preparedOverview(count: photos.count) { photos[$0] }
    for columns in [15, 31] {
      let canvas = CalendarDenseCanvas(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
      let assets = (0..<6000).map { CalendarGridAsset(id: "atlas-\($0)", date: nil, aspect: 1) }
      let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: columns,
        originalAspect: false, leadingSlots: columns / 2)
      canvas.reset(geometry, columns: columns, fill: true)
      canvas.overviewPixels = overview
      canvas.tableLookup = { photos[$0] }
      canvas.renderQueue.suspend()
      defer { canvas.stop(); canvas.renderQueue.resume() }
      var timings: [Double] = []
      for fraction: CGFloat in [0, 0.8, 0.2, 0.6, 0.1] {
        let visible = canvas.bounds.offsetBy(dx: 0, dy: (geometry.height - canvas.bounds.height) * fraction)
        let start = CACurrentMediaTime()
        canvas.update(visible: visible, scale: 3)
        timings.append((CACurrentMediaTime() - start) * 1000)
        XCTAssertEqual(canvas.coverage(in: visible), 1)
        func layers(_ layer: CALayer) -> Int { 1 + (layer.sublayers ?? []).reduce(0) { $0 + layers($1) } }
        XCTAssertLessThan(layers(canvas.layer), 100, "Thousands of photos share a bounded strip-layer set")
        for index in geometry.visible(in: visible) where index.isMultiple(of: 83) {
          let image = try XCTUnwrap(canvas.displayedImage(index)?.cgImage)
          let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: color, bitmapInfo: info.rawValue))
          context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
          let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
          XCTAssertEqual(Int(bytes[0]), index % 251, accuracy: 1)
          XCTAssertEqual(Int(bytes[1]), index / 251, accuracy: 1)
          XCTAssertEqual(Int(bytes[2]), (index * 7) % 251, accuracy: 1)
        }
      }
      print("DEEP_GRID unique atlas columns=\(columns) update_ms=\(timings)")
    }
  }

  @MainActor func testDenseAtlasHolesPreserveAlreadyPublishedPhotos() async throws {
    func photo(_ color: UIColor) -> CGImage {
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      return UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
        color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
      }.cgImage!
    }
    let red = photo(.red), blue = photo(.blue)
    let canvas = CalendarDenseCanvas(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
    let assets = (0..<2000).map { CalendarGridAsset(id: "holes-\($0)", date: nil, aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 31,
      originalAspect: false, leadingSlots: 15)
    canvas.reset(geometry, columns: 31, fill: true)
    canvas.tableLookup = { $0.isMultiple(of: 2) ? red : nil }
    canvas.update(visible: canvas.bounds, scale: 3)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in canvas.isReady(in: canvas.bounds) }, object: nil)
    await fulfillment(of: [ready], timeout: 5)
    canvas.renderQueue.suspend()
    defer { canvas.stop(); canvas.renderQueue.resume() }
    canvas.overviewPixels = await preparedOverview(count: assets.count) { $0.isMultiple(of: 2) ? nil : blue }
    canvas.tableLookup = { $0.isMultiple(of: 2) ? nil : blue }
    canvas.update(visible: canvas.bounds, scale: 3)
    XCTAssertEqual(canvas.coverage(in: canvas.bounds), 1)
    let format = UIGraphicsImageRendererFormat(); format.scale = 3
    let rendered = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
      canvas.layer.render(in: context.cgContext)
    }.cgImage!
    for index in [0, 1, 30, 31, 248, 249] {
      let frame = geometry.tiles[index].frame
      let sample = try XCTUnwrap(rendered.cropping(to: CGRect(x: frame.midX * 3, y: frame.midY * 3, width: 1, height: 1)))
      let info = CGImageAlphaInfo.noneSkipLast.rawValue
      let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info))
      context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
      XCTAssertGreaterThan(Int(bytes[index.isMultiple(of: 2) ? 0 : 2]), 240)
      XCTAssertLessThan(Int(bytes[index.isMultiple(of: 2) ? 2 : 0]), 15)
    }
  }

  @MainActor func testDensePresentationCoverOwnsBytesAfterMappedSlotChanges() async throws {
    let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: 48 * 48 * 4)
    pixels.initialize(repeating: 77, count: 48 * 48 * 4)
    defer { pixels.deallocate() }
    let provider = try XCTUnwrap(CGDataProvider(dataInfo: nil, data: pixels, size: 48 * 48 * 4,
      releaseData: { _, _, _ in }))
    let image = try XCTUnwrap(CGImage(width: 48, height: 48, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: true, intent: .defaultIntent))
    let canvas = CalendarDenseCanvas(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
    let assets = (0..<2000).map { CalendarGridAsset(id: "mapped-\($0)", date: nil, aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 31, originalAspect: false)
    canvas.reset(geometry, columns: 31, fill: true)
    canvas.overviewPixels = await preparedOverview(count: assets.count) { _ in image }
    canvas.tableLookup = { _ in image }
    canvas.renderQueue.suspend()
    defer { canvas.stop(); canvas.renderQueue.resume() }
    canvas.update(visible: canvas.bounds, scale: 3)
    pixels.update(repeating: 0, count: 48 * 48 * 4)
    let retained = try XCTUnwrap(canvas.displayedImage(0)?.cgImage?.dataProvider?.data)
    XCTAssertEqual(CFDataGetBytePtr(retained)?[0], 77, "Evicting or clearing a decoded slot cannot change its presented identity")
  }

  @MainActor func testCompactBadgeArtworkMatchesNativeMarksAndRestoresNativeViews() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 3
    func render(_ layer: CALayer, size: CGSize) -> UIImage {
      UIGraphicsImageRenderer(size: size, format: format).image { context in layer.render(in: context.cgContext) }
    }
    let assets = (0..<1000).map { CalendarGridAsset(id: "marks-\($0)", date: nil, aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 3, originalAspect: false)
    for style in [UIUserInterfaceStyle.light, .dark] {
      for selected in [false, true] {
        let stage = CalendarZoomStage(frame: CGRect(x: 0, y: 0, width: 440, height: 500), columns: 31,
          pitch: 440 / 31, focus: CGPoint(x: 220, y: 250), displayScale: 3)
        stage.overrideUserInterfaceStyle = style
        stage.configureDecorations = { badges, _ in
          badges.media(kind: "motion", duration: nil)
          badges.duration.text = "1:23"
          badges.burstCount.text = "12"
          badges.selection(selected, enabled: true)
          badges.backupState("sending", visible: !selected)
        }
        let face = stage.addFace(columns: 3, geometry: geometry, focus: geometry.tiles[500].frame.origin,
          pitch: CalendarGridGeometry.pitch(width: 440, columns: 3), opacity: 1)
        let tile = try XCTUnwrap(face.tiles.values.first), compact = try XCTUnwrap(tile.compactDecorations)
        let reference = CalendarTileDecorations(frame: CGRect(origin: .zero, size: compact.artwork.size))
        reference.overrideUserInterfaceStyle = style
        reference.apply(compact.artwork.state); reference.thumbnail(hasImage: true, cloud: false)
        reference.layoutIfNeeded()
        XCTAssertEqual(compact.artwork.state.burstCount, "12")
        XCTAssertFalse(reference.burstCount.isHidden)
        XCTAssertTrue(compact.artwork.marks.contains { $0.1 == reference.burstCount.frame.insetBy(dx: -6, dy: -6) },
          "The compact stage must retain the burst count added by shared library cells")
        let comparison = CalendarZoomStage.CompactDecorations(compact.artwork, actions: [:])
        comparison.display(hasImage: true, cloud: false)
        let native = render(reference.layer, size: compact.artwork.size)
        let flattened = render(comparison.layer, size: compact.artwork.size)
        let a = try XCTUnwrap(native.cgImage?.dataProvider?.data)
        let b = try XCTUnwrap(flattened.cgImage?.dataProvider?.data)
        XCTAssertEqual(CFDataGetLength(a), CFDataGetLength(b))
        let aa = try XCTUnwrap(CFDataGetBytePtr(a)), bb = try XCTUnwrap(CFDataGetBytePtr(b))
        let count = min(CFDataGetLength(a), CFDataGetLength(b))
        let difference = (0..<count).reduce(0) { $0 + abs(Int(aa[$1]) - Int(bb[$1])) }
        let mean = Double(difference) / Double(count)
        print("DEEP_GRID badge_pixels style=\(style.rawValue) selected=\(selected) mean_error=\(mean)")
        XCTAssertLessThan(mean, 2, "Native-rendered artwork must preserve the actual marks, shadows and alignment")
        for (name, image) in [("native", native), ("compact", flattened)] {
          let attachment = XCTAttachment(image: image)
          attachment.name = "badge-\(style.rawValue)-\(selected)-\(name)"; attachment.lifetime = .keepAlways
          add(attachment)
        }
        stage.pitch = face.pitch; stage.layoutAll()
        XCTAssertTrue(face.tiles.values.allSatisfy { $0.compactDecorations == nil && $0.decorations != nil })
        stage.stop()
      }
    }
  }

  @MainActor func testSettleRestoresNativeBadgesOnlyInTargetViewport() throws {
    let assets = (0..<55000).map { CalendarGridAsset(id: "settle-\($0)", date: nil, aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 5, originalAspect: false)
    let stage = CalendarZoomStage(frame: CGRect(x: 0, y: 0, width: 440, height: 956), columns: 31,
      pitch: 440 / 31, focus: CGPoint(x: 220, y: 478), displayScale: 3)
    stage.configureDecorations = { badges, index in
      badges.duration.text = "1:23"
      badges.liveMark.image = index.isMultiple(of: 2) ? CalendarTileDecorations.Style.symbol("livephoto") : nil
      badges.selection(index.isMultiple(of: 3), enabled: true)
    }
    let face = stage.addFace(columns: 5, geometry: geometry, focus: geometry.tiles[27500].frame.origin,
      pitch: CalendarGridGeometry.pitch(width: 440, columns: 5), opacity: 1)
    stage.show(5, animated: false)
    stage.setSettle(pitch: face.pitch, focus: stage.focus, velocity: 0, done: {})
    let visible = face.tiles.values.filter { $0.frame.intersects(stage.bounds) }
    let offscreen = face.tiles.values.filter { !$0.frame.intersects(stage.bounds) }
    XCTAssertFalse(visible.isEmpty); XCTAssertGreaterThan(offscreen.count, 100)
    XCTAssertTrue(visible.allSatisfy { $0.decorations != nil && $0.compactDecorations == nil })
    XCTAssertTrue(offscreen.allSatisfy { $0.compactDecorations != nil }, "Release-only tiles keep their exact native-rendered artwork during the settle")
    stage.advance(to: CACurrentMediaTime() + 3)
    XCTAssertTrue(face.tiles.values.allSatisfy { $0.compactDecorations == nil && $0.decorations != nil })
    stage.stop()
  }

  @MainActor func testStageAdoptsBackgroundOwnedCopyWithoutDowngrade() async throws {
    let c = CalendarGridController()
    c.assets = [CalendarGridAsset(id: "owned-stage", date: nil, aspect: 1)]
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    func image(_ side: CGFloat) -> UIImage {
      UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
        UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
      }
    }
    let sharp = image(48), preview = image(8)
    c.prepareOverviewImage = { _ in sharp.cgImage }
    var requests = 0
    c.requestImage = { _, _, _ in requests += 1; return {} }
    let tile = CalendarZoomStage.Tile()
    tile.display(preview)
    let cancel = c.stageTile(tile.photo, asset: 0, pixels: 40)
    let delivered = expectation(for: NSPredicate { _, _ in tile.presentedImage?.cgImage?.width == 48 }, evaluatedWith: nil)
    await fulfillment(of: [delivered], timeout: 5)
    XCTAssertEqual(requests, 0, "A sufficient owning table copy avoids a redundant PhotoKit request")
    tile.display(image(4))
    XCTAssertEqual(tile.presentedImage?.cgImage?.width, 48)
    cancel?()
  }

  @MainActor func testStageFallsBackToHostWhenOwnedCopyIsMissingOrTooSmall() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let small = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { _ in }.cgImage!
    for available in [false, true] {
      let c = CalendarGridController()
      c.assets = [CalendarGridAsset(id: "fallback-\(available)", date: nil, aspect: 1)]
      c.prepareOverviewImage = { _ in available ? small : nil }
      let requested = expectation(description: "Host resolves missing or inadequate copied image")
      c.requestImage = { _, _, _ in requested.fulfill(); return {} }
      let tile = CalendarZoomStage.Tile()
      let cancel = c.stageTile(tile.photo, asset: 0, pixels: 64)
      await fulfillment(of: [requested], timeout: 5)
      cancel?()
    }
  }

  @MainActor func testStageCopiesColdTableOffMainAndRejectsChangedRevision() async throws {
    let c = CalendarGridController()
    c.assets = [CalendarGridAsset(id: "cold-stage", date: nil, aspect: 1)]
    let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { context in
      UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    }.cgImage!
    let entered = expectation(description: "Cold copy on worker"), gate = DispatchSemaphore(value: 0)
    c.prepareOverviewImage = { _ in
      XCTAssertFalse(Thread.isMainThread)
      entered.fulfill(); gate.wait()
      return image
    }
    c.requestImage = { _, _, _ in { } }
    c.storedImage = { _, _ in XCTFail("Stage must not expose a mapped provider"); return nil }
    let tile = CalendarZoomStage.Tile()
    let cancel = c.stageTile(tile.photo, asset: 0, pixels: 64)
    await fulfillment(of: [entered], timeout: 5)
    c.assets[0].revision += 1
    gate.signal()
    let unchanged = expectation(description: "Changed identity rejects delayed pixels")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { unchanged.fulfill() }
    await fulfillment(of: [unchanged], timeout: 5)
    XCTAssertNil(tile.photo.contents)
    cancel?()
  }

  @MainActor func testStageArrivalsRetainPixelsWithoutImplicitContentsAnimations() throws {
    let c = CalendarGridController()
    c.assets = (0..<1000).map { CalendarGridAsset(id: "arrival-\($0)", date: nil, aspect: 1) }
    let g = CalendarGridGeometry(assets: c.assets, level: .all, width: 440, columns: 5, originalAspect: false)
    let stage = CalendarZoomStage(frame: CGRect(x: 0, y: 0, width: 440, height: 956), columns: 5,
      pitch: CalendarGridGeometry.pitch(width: 440, columns: 5), focus: CGPoint(x: 220, y: 478), displayScale: 3)
    c.stage = stage
    var arrivals: [(UIImage?, Bool) -> Void] = []
    c.requestImage = { _, _, done in arrivals.append(done); return {} }
    stage.configureTile = { [weak c] layer, index, pixels in c?.stageTile(layer, asset: index, pixels: pixels) }
    let face = stage.addFace(columns: 5, geometry: g, focus: g.tiles[500].frame.origin,
      pitch: CalendarGridGeometry.pitch(width: 440, columns: 5), opacity: 1)
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    }
    XCTAssertFalse(arrivals.isEmpty)
    CATransaction.begin(); CATransaction.setAnimationDuration(1)
    arrivals.forEach { $0(photo, false) }
    CATransaction.commit()
    XCTAssertEqual(stage.loaded(face), 1)
    for tile in face.tiles.values {
      XCTAssertNotNil(tile.presentedImage); XCTAssertNotNil(tile.photo.contents)
      XCTAssertNil(tile.photo.animation(forKey: "contents"))
    }
    stage.stop(); c.stage = nil
  }

  func testDenseCalendarGroupingKeepsPeriodBoundariesAndMissingDates() throws {
    let calendar = Calendar.current
    let boundary = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
    let prior = boundary.addingTimeInterval(-1)
    let dates: [Date?] = [prior, prior, boundary, boundary, nil, boundary]
    let assets = dates.enumerated().map { CalendarGridAsset(id: "boundary-\($0.offset)", date: $0.element, aspect: 1) }
    for columns in [15, 31] {
      for items in [assets, Array(assets.reversed())] {
        let g = CalendarGridGeometry(assets: items, level: .all, width: 440,
          columns: columns, originalAspect: false, leadingSlots: columns / 2)
        func title(_ date: Date?) -> String {
          guard let date else { return NSLocalizedString("design_capture_unknown", comment: "") }
          return columns == 31 ? date.formatted(.dateTime.year()) : date.formatted(.dateTime.year().month(.wide))
        }
        let expected = items.first?.id == assets.first?.id
          ? [title(prior), title(boundary), title(nil), title(boundary)]
          : [title(boundary), title(nil), title(boundary), title(prior)]
        XCTAssertEqual(g.headings.map(\.0), expected)
        XCTAssertEqual(g.tiles.map(\.id), items.map(\.id))
      }
    }
  }

  @MainActor func testDenseReadinessTracksArrivalsAndRecycledTilesThroughReversal() {
    let assets = (0..<12000).map { CalendarGridAsset(id: "ready-\($0)", date: nil, aspect: 1) }
    let pitch: CGFloat = 440 / 31
    let stage = CalendarZoomStage(frame: CGRect(x: 0, y: 0, width: 440, height: 956),
      columns: 31, pitch: pitch, focus: CGPoint(x: 220, y: 478), displayScale: 3)
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    stage.configureTile = { layer, _, _ in layer.contents = nil; return nil }
    let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440, columns: 31, originalAspect: false)
    let face = stage.addFace(columns: 31, geometry: geometry,
      focus: CGPoint(x: geometry.tiles[6000].frame.midX, y: geometry.tiles[6000].frame.midY), pitch: pitch, opacity: 1)
    func verify() {
      let actual = face.tiles.values.filter { $0.photo.contents != nil }.count
      XCTAssertEqual(stage.loaded(face), CGFloat(actual) / CGFloat(face.tiles.count), accuracy: 0.000001)
    }
    verify()
    for tile in face.tiles.values.prefix(face.tiles.count / 2) { tile.display(photo); tile.display(photo) }
    verify()
    for factor: CGFloat in [0.8, 1.2, 0.9, 1, 0.8, 1] {
      stage.pitch = pitch * factor; stage.layoutAll(); verify()
      for tile in face.tiles.values { tile.display(photo) }
      verify(); XCTAssertEqual(stage.loaded(face), 1)
    }
    stage.stop()
  }

  @MainActor func testDenseScrollPublishesAheadOfRasterBacklogAndRetainsReturnPixels() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    func photo(_ color: UIColor) -> CGImage {
      UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
        color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
      }.cgImage!
    }
    func rgb(_ image: CGImage) throws -> [UInt8] {
      let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
      return Array(UnsafeBufferPointer(start: data, count: 3))
    }
    let even = photo(.systemBlue), odd = photo(.systemOrange)
    for columns in [15, 31] {
      let canvas = CalendarDenseCanvas(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
      let assets = (0..<12000).map { CalendarGridAsset(id: "scroll-\($0)", date: nil, aspect: 1) }
      let geometry = CalendarGridGeometry(assets: assets, level: .all, width: 440,
        columns: columns, originalAspect: false, leadingSlots: columns / 2)
      canvas.tableLookup = { $0.isMultiple(of: 2) ? even : odd }
      canvas.request = { _, _, _ in XCTFail("Decoded table hits must not request media"); return nil }
      canvas.reset(geometry, columns: columns, fill: true)
      let gate = DispatchSemaphore(value: 0)
      defer { gate.signal(); canvas.stop() }
      canvas.update(visible: canvas.bounds, scale: 3)
      let backlog = expectation(description: "Subsequent raster work is blocked")
      canvas.renderQueue.async { backlog.fulfill(); gate.wait() }
      await fulfillment(of: [backlog], timeout: 5)
      let painted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        canvas.coverage(in: canvas.bounds) == 1
      }, object: nil)
      // The first ready bitmaps must reach the display while subsequent raster
      // jobs are still blocked, without another hop onto that queue.
      await fulfillment(of: [painted], timeout: 5)
      XCTAssertTrue(canvas.isReady(in: canvas.bounds))
      let far = canvas.bounds.offsetBy(dx: 0, dy: geometry.height * 0.7)
      for viewport in [far, canvas.bounds, far, canvas.bounds] {
        canvas.update(visible: viewport, scale: 3)
        if viewport == canvas.bounds {
          XCTAssertEqual(canvas.coverage(in: viewport), 1, "Return scrolling reuses published strips immediately")
          let visible = geometry.visible(in: viewport).filter { geometry.tiles[$0].frame.intersects(viewport) }
          for index in visible {
            let image = try XCTUnwrap(canvas.displayedImage(index)?.cgImage)
            XCTAssertEqual(try rgb(image), try rgb(index.isMultiple(of: 2) ? even : odd))
          }
        }
      }
      gate.signal()
      let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        canvas.isReady(in: canvas.bounds) && canvas.coverage(in: canvas.bounds) == 1
      }, object: nil)
      await fulfillment(of: [settled], timeout: 5)
      // Geometry reset invalidates the old cache; an unresolved different
      // library must never inherit the previous library's visible pixels.
      canvas.stop(); canvas.tableLookup = { _ in nil }
      canvas.request = { _, _, _ in nil }
      canvas.update(visible: canvas.bounds, scale: 3)
      XCTAssertEqual(canvas.coverage(in: canvas.bounds), 0)
    }
  }

  @MainActor func testDenseCanvasRetainsSynchronousArrivalsAndPublishedPixels() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64),format: format).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
    }
    let canvas = CalendarDenseCanvas(frame: CGRect(x: 0,y: 0,width: 402,height: 874))
    let assets = (0..<12000).map { CalendarGridAsset(id: "photo-\($0)",date: nil,aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets,level: .all,width: 402,columns: 31,originalAspect: false)
    var cache: [Int: UIImage] = [:]
    canvas.cachedImage = { cache[$0] }
    canvas.request = { asset,_,done in cache[asset] = photo; done(photo); return {} }
    canvas.reset(geometry,columns: 31,fill: true)
    canvas.update(visible: canvas.bounds,scale: 1)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in canvas.isReady(in: canvas.bounds) },object: nil)
    await fulfillment(of: [ready],timeout: 5)
    // A cached completion can precede context creation. Publication alone is
    // insufficient: the bitmap must actually contain those completed tiles.
    let painted = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in canvas.displayedImage(500) != nil },object: nil)
    await fulfillment(of: [painted],timeout: 5)
    cache = [:]
    let retained = try XCTUnwrap(canvas.displayedImage(500))
    XCTAssertGreaterThan(retained.cgImage?.width ?? 0,0,"Eviction must not erase pixels already displayed by the canvas")
    // Reuse strips while their old publication is still queued. A publication
    // from one generation cannot suppress the new generation's bitmap.
    for y: CGFloat in [2000,0,2400,0] { canvas.update(visible: canvas.bounds.offsetBy(dx: 0,dy: y),scale: 1) }
    let recycled = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
      canvas.isReady(in: canvas.bounds) && canvas.displayedImage(500) != nil
    },object: nil)
    await fulfillment(of: [recycled],timeout: 5)
    canvas.stop()
  }

  @MainActor func testDenseHandoffWaitsForBitmapAndNextGestureSurvivesCacheEviction() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64),format: format).image { ctx in
      UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
    }
    let c = controller(6000,image: photo)
    c.place(40000)
    c.denseCanvas.renderQueue.suspend()
    var suspended = true
    defer { if suspended { c.denseCanvas.renderQueue.resume() }; c.stopMotion() }
    c.density(columns: 31,at: 3000)
    c.completeStage()
    try await Task.sleep(for: .milliseconds(60))
    XCTAssertNotNil(c.adoptionCover,"A delayed bitmap renderer must not expose empty strips after the animation ends")
    XCTAssertFalse(c.denseCanvas.isReady(in: c.grid.bounds))
    c.denseCanvas.renderQueue.resume(); suspended = false
    let adopted = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
      c.denseCanvas.isReady(in: c.grid.bounds) && c.adoptionCover == nil
    },object: nil)
    await fulfillment(of: [adopted],timeout: 5)
    c.transitionImages.removeAllObjects(); c.transitionSmallImages.removeAllObjects()
    c.requestImage = { _,_,done in done(nil,false); return {} }
    c.beginStage(point: CGPoint(x: 201,y: c.grid.contentOffset.y+437),item: nil,distance: 300)
    let stage = try XCTUnwrap(c.stage),face = try XCTUnwrap(stage.faces[31])
    XCTAssertGreaterThan(stage.loaded(face),0.95,"The new gesture takes its source from the displayed bitmap, even when all image caches miss")
    let tile = try XCTUnwrap(face.tiles.values.first { $0.convert($0.bounds,to: stage.layer).intersects(stage.bounds) })
    let before = tile.convert(tile.bounds,to: stage.layer)
    stage.pitch *= 1.00001; stage.layoutAll()
    let after = tile.convert(tile.bounds,to: stage.layer)
    XCTAssertEqual(after.width/before.width,1.00001,accuracy: 0.000001,"Grouped dense scaling follows the fingers continuously")
  }

  @MainActor func testSingleColumnKeepsAvailableFallbackUntilUncroppedRenditionArrives() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    func bitmap(_ size: CGSize) -> UIImage { UIGraphicsImageRenderer(size: size,format: format).image { _ in } }
    let fallback = bitmap(CGSize(width: 64,height: 64)), full = bitmap(CGSize(width: 768,height: 1024))
    let c = controller(1)
    c.assets = [CalendarGridAsset(id: "portrait",date: nil,aspect: 0.75)]
    c.columns = 1
    var deliver: ((UIImage?,Bool)->Void)?
    c.requestUncroppedImage = { _,_,done in deliver = done; done(fallback,false); return {} }
    c.layout.geometry = CalendarGridGeometry(assets: c.assets,level: .all,width: 402,columns: 1,originalAspect: false)
    let cell = try XCTUnwrap(c.collectionView(c.grid,cellForItemAt: IndexPath(item: 0,section: 0)) as? CalendarGridCell)
    XCTAssertTrue(cell.image.image === fallback,"A cropped fallback is usable while full-aspect pixels are pending")
    XCTAssertTrue(cell.placeholder.isHidden)
    deliver?(full,false); deliver?(fallback,false); deliver?(nil,true)
    XCTAssertTrue(cell.image.image === full,"Late fallback/nil results cannot erase or downgrade the visible photo")
    XCTAssertTrue(cell.placeholder.isHidden)
    let tile = CalendarZoomStage.Tile(); tile.columns = 1
    c.rememberImage(bitmap(CGSize(width: 1024,height: 1024)),for: c.assets[0])
    deliver = nil
    _ = c.stageTile(tile.photo,asset: 0,pixels: 512)
    XCTAssertNotNil(deliver,"The one-column target requests its own crop before it becomes the current density")
    deliver?(full,false)
    XCTAssertTrue(tile.presentedImage === full)
  }


  @MainActor func testSelectionHidesVideoDurationAtOrdinaryDensities() {
    for side: CGFloat in [80, 132, 440] {
      let decorations = CalendarTileDecorations(frame: CGRect(x: 0,y: 0,width: side,height: side))
      decorations.duration.text = "1:23"
      decorations.selection(true, enabled: true)
      decorations.setNeedsLayout(); decorations.layoutIfNeeded()
      XCTAssertTrue(decorations.duration.isHidden, "The selection mark replaces the duration")
      decorations.selection(false, enabled: true)
      decorations.setNeedsLayout(); decorations.layoutIfNeeded()
      XCTAssertFalse(decorations.duration.isHidden)
    }
  }

  @MainActor func testMediaRingHasOneLoadingOwnerAndOnlyRealProgress() {
    let ring = MediaLoadingIndicator(frame: CGRect(x: 0,y: 0,width: 36,height: 36))
    ring.layoutIfNeeded(); ring.update(state: .indeterminate, identity: "photo")
    XCTAssertFalse(ring.isHidden); XCTAssertNil(ring.accessibilityValue)
    XCTAssertFalse(ring.isUserInteractionEnabled)
    ring.update(state: .progress(0.62), identity: "photo")
    XCTAssertEqual(ring.arc.strokeEnd,0.62,accuracy: 0.001)
    XCTAssertEqual(ring.accessibilityValue,"62%")
    XCTAssertNil(ring.arc.animation(forKey: "loading.rotation"))
    ring.update(state: .failed, identity: "photo")
    XCTAssertFalse(ring.isHidden); XCTAssertTrue(ring.isUserInteractionEnabled)
    XCTAssertTrue(ring.arc.isHidden); XCTAssertFalse(ring.symbol.isHidden)
    ring.update(state: .hidden, identity: "photo")
    XCTAssertTrue(ring.accessibilityElementsHidden, "A finished load hides the ring without removing its slot")
  }

  @MainActor func testNativePageExistsBeforeImageArrivalAndKeepsFlightPose() throws {
    let fetch = PHAsset.fetchAssets(with: .image,options: photoLibraryFetchOptions())
    guard let asset = fetch.firstObject else { throw XCTSkip("Import synthetic fixtures") }
    let library = PhotoLibraryModel(), model = MediaPreviewModel(asset: asset)
    let session = MediaPreviewSession(asset: asset,library: library)
    let page = NativeMediaPage(model: model,session: session)
    page.loadViewIfNeeded(); page.view.frame = CGRect(x: 0,y: 0,width: 402,height: 874); page.view.layoutIfNeeded()
    let surface = page.surface, bounds = surface.bounds
    XCTAssertGreaterThan(bounds.width,0,"An empty poster cannot skip the entry animation")
    page.flightLocked = true
    let pose = CGAffineTransform(translationX: -60,y: -120).scaledBy(x: 0.2,y: 0.2)
    surface.transform = pose
    page.refresh(); page.view.setNeedsLayout(); page.view.layoutIfNeeded()
    XCTAssertTrue(page.surface === surface); XCTAssertEqual(surface.transform,pose)
    XCTAssertEqual(surface.bounds,bounds,"Readiness and layout must not replace the animated rectangle")
  }

  @MainActor func testVideoReadinessKeepsPosterAndSameNodeThroughFlight() async throws {
    let fetch = PHAsset.fetchAssets(with: .video,options: photoLibraryFetchOptions())
    guard let asset = fetch.firstObject else { throw XCTSkip("Import synthetic video") }
    let poster = UIGraphicsImageRenderer(size: CGSize(width: 160,height: 90)).image { c in UIColor.orange.setFill(); c.fill(CGRect(x: 0,y: 0,width: 160,height: 90)) }
    let library = PhotoLibraryModel(), model = MediaPreviewModel(asset: asset,poster: poster)
    let session = MediaPreviewSession(asset: asset,library: library)
    let page = NativeMediaPage(model: model,session: session), window = UIWindow(frame: CGRect(x: 0,y: 0,width: 402,height: 874))
    window.rootViewController = page; window.makeKeyAndVisible(); page.view.layoutIfNeeded()
    defer { model.cancel(); window.isHidden = true }
    let surface = page.surface, rect = surface.bounds
    page.flightLocked = true; model.load(promptForCloud: false)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in page.videoReady },object: nil)
    await fulfillment(of: [ready],timeout: 10)
    XCTAssertTrue(page.surface === surface); XCTAssertEqual(surface.bounds,rect)
    XCTAssertNotNil(page.scroll.photo.image)
    XCTAssertFalse(page.scroll.photo.isHidden, "The poster owns the visible face until the flight ends")
    XCTAssertFalse(page.video.view.isUserInteractionEnabled)
    XCTAssertTrue(page.video.view.accessibilityElementsHidden)
    XCTAssertEqual(page.video.view.alpha, 1, "AVKit prepares in its normal render tree behind the poster")
    let layers = page.scroll.media.subviews
    XCTAssertGreaterThan(try XCTUnwrap(layers.firstIndex(of: page.scroll.photo)),
      try XCTUnwrap(layers.firstIndex(of: page.video.view)))
    page.flightLocked = false
    XCTAssertTrue(page.scroll.photo.isHidden); XCTAssertTrue(page.video.parent === page)
    XCTAssertTrue(page.video.view.isUserInteractionEnabled)
    XCTAssertFalse(page.video.view.accessibilityElementsHidden)
    XCTAssertTrue(page.surface === surface); XCTAssertEqual(surface.bounds, rect)
  }

  @MainActor func testMediaDragKeepsGrabbedPointUnderFingerWhileScaling() {
    let center = CGPoint(x: 201,y: 437), origin = CGPoint(x: 130,y: 350)
    for point in [CGPoint(x: 48,y: 183),CGPoint(x: -65,y: 120),CGPoint(x: 20,y: -30)] {
      let pose = MediaFlightGeometry.drag(origin: origin,center: center,translation: point)
      let local = CGPoint(x: origin.x-center.x,y: origin.y-center.y).applying(pose)
      XCTAssertEqual(local.x+center.x,origin.x+point.x,accuracy: 0.001)
      XCTAssertEqual(local.y+center.y,origin.y+point.y,accuracy: 0.001)
    }
  }
  @MainActor func testMediaFlightCropMeetsPortraitAndLandscapeGridTargets() {
    for size in [CGSize(width: 402,height: 302),CGSize(width: 402,height: 750)] {
      let bounds = CGRect(origin: .zero,size: size)
      let fitted = CGRect(x: 0,y: (874-size.height)/2,width: size.width,height: size.height)
      for thumbnail in [CGRect(x: 90,y: 150,width: 78,height: 78),CGRect(x: 0,y: 470,width: 134,height: 90)] {
        let flight = MediaFlightGeometry(bounds: bounds,fitted: fitted,thumbnail: thumbnail)
        XCTAssertTrue(bounds.insetBy(dx: -0.001,dy: -0.001).contains(flight.crop))
        let scale = flight.transform.a
        XCTAssertEqual(flight.transform.d,scale)
        XCTAssertEqual(flight.crop.width*scale,thumbnail.width,accuracy: 0.001)
        XCTAssertEqual(flight.crop.height*scale,thumbnail.height,accuracy: 0.001)
        XCTAssertEqual(fitted.midX+flight.transform.tx,thumbnail.midX,accuracy: 0.001)
        XCTAssertEqual(fitted.midY+flight.transform.ty,thumbnail.midY,accuracy: 0.001)
      }
    }
  }

  @MainActor func testFilmstripFractionalFocusIsContinuousAndLookupRemainsBounded() throws {
    let source = MediaStripTestSource(), layout = MediaFilmstripLayout()
    let strip = UICollectionView(frame: CGRect(x: 0,y: 0,width: 402,height: 46),collectionViewLayout: layout)
    strip.register(UICollectionViewCell.self,forCellWithReuseIdentifier: "tile")
    strip.dataSource = source; strip.reloadData(); strip.layoutIfNeeded()
    layout.current = 25000; layout.aspect = 4/3; layout.neighborAspects = [25000: 4/3,25001: 0.75]
    layout.focus = 25000.5
    let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 25000,section: 0)))
    let next = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 25001,section: 0)))
    XCTAssertGreaterThan(first.frame.width,20); XCTAssertGreaterThan(next.frame.width,20)
    XCTAssertGreaterThan(next.frame.minX,first.frame.maxX)
    let visible = layout.layoutAttributesForElements(in: CGRect(x: layout.focusCenter-201,y: 0,width: 402,height: 46)) ?? []
    XCTAssertLessThan(visible.count,25,"Only visible filmstrip cells are visited in a 55k library")
    layout.focus = 25001-0.000001
    let before = layout.focusCenter
    layout.current = 25001; layout.focus = nil; layout.aspect = 0.75
    XCTAssertEqual(layout.focusCenter,before,accuracy: 0.001,"Adopting page identity must not recenter the strip discontinuously")
    layout.expansion = 0; layout.invalidateLayout()
    for index in [0,25000,54999] { XCTAssertEqual(layout.nearest(layout.center(index)),index) }
  }

  /// The launch density is remembered; fixtures start from the default three columns.
  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: CalendarGridController.densityKey)
  }
  @MainActor private func settle(_ controller: CalendarGridController) {
    guard let animator = controller.spring else { return }
    if animator.state == .inactive { animator.startAnimation() }
    animator.stopAnimation(false); animator.finishAnimation(at:.end)
  }

  @MainActor func testRapidHierarchyReplacementCancelsWithoutCommittingOldCompletion() {
    let c = CalendarGridController()
    let assets = (0..<55000).map { CalendarGridAsset(id:"stress-\($0)",
      date:Date(timeIntervalSince1970:1577836800+Double($0)*2700),aspect:1) }
    c.assets = assets; c.loadViewIfNeeded()
    c.view.frame = CGRect(x:0,y:0,width:402,height:874); c.view.layoutIfNeeded()
    for step in 0..<120 {
      c.changeLevel(step % 2 == 0 ? .months : .years,asset:assets.count-10,from:nil)
      if step % 10 == 0 { c.replaceAssets(assets) }
    }
    c.stopMotion()
    XCTAssertNil(c.spring); XCTAssertNil(c.transitionOverlay)
    XCTAssertFalse(c.changing); XCTAssertEqual(c.grid.alpha,1)
    XCTAssertTrue(c.grid.visibleCells.allSatisfy { !$0.isHidden })
  }
  @MainActor func testSmallerLatePosterCannotReplacePreparedSharperPixels() {
    let c = CalendarGridController()
    let image: (CGFloat)->UIImage = { side in
      let f = UIGraphicsImageRendererFormat(); f.scale = 1
      return UIGraphicsImageRenderer(size:CGSize(width:side,height:side),format:f).image { _ in }
    }
    let sharp = image(512),small = image(64)
    c.assets = [CalendarGridAsset(id: "photo", date: nil, aspect: 1)]
    c.rememberImage(sharp, for: c.assets[0]); c.rememberImage(small, for: c.assets[0])
    XCTAssertTrue(c.transitionImages.object(forKey:"photo") === sharp)
    XCTAssertTrue(c.transitionSmallImages.object(forKey:"photo") === small)
    let layer = CALayer()
    _ = c.stageTile(layer, asset: 0, pixels: 64)
    XCTAssertEqual((layer.contents as! CGImage).width, 64, "Dense tiles use their small tier while sharper return pixels remain cached")
  }

  @MainActor func testTransitionImagesRejectEditedAndRemovedIdentitiesWithoutDroppingUnchangedPixels() throws {
    let c = controller(3)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { _ in }
    let old = c.assets
    for asset in old { c.rememberImage(image, for: asset) }
    var next = old
    next[0].revision += 1
    next.remove(at: 1)
    c.replaceAssets(next)
    for id in [old[0].id, old[1].id] {
      XCTAssertNil(c.transitionImages.object(forKey: id as NSString))
      XCTAssertNil(c.transitionSmallImages.object(forKey: id as NSString))
    }
    XCTAssertTrue(c.transitionImages.object(forKey: old[2].id as NSString) === image)
    XCTAssertTrue(c.transitionSmallImages.object(forKey: old[2].id as NSString) === image)
    for asset in old.prefix(2) { c.rememberImage(image, for: asset) }
    XCTAssertNil(c.transitionImages.object(forKey: old[0].id as NSString))
    XCTAssertNil(c.transitionImages.object(forKey: old[1].id as NSString))
    c.configureDenseCanvas()
    XCTAssertNil(c.denseCanvas.cachedImage(0), "Revised media cannot use old transition pixels as a menu/transition seed")
    c.rememberImage(image, for: next[0])
    XCTAssertTrue(c.denseCanvas.cachedImage(0) === image)
  }

  @MainActor func testUnifiedThumbnailClearRejectsLateCellDenseAndWarmCallbacksAndAllowsFreshRequests() throws {
    let c = controller(30)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { _ in }
    var arrivals: [(UIImage?, Bool) -> Void] = []
    c.requestImage = { _, _, done in arrivals.append(done); return {} }
    c.prefetchImage = c.requestImage
    c.configureDenseCanvas()
    let cell = try XCTUnwrap(c.collectionView(c.grid, cellForItemAt: IndexPath(item: 0, section: 0)) as? CalendarGridCell)
    let denseCancel = c.denseCanvas.request(1, 64) { _ in XCTFail("A cleared dense request cannot publish pixels") }
    c.warmZoomViewport()
    c.warmAdjacentScenes()
    XCTAssertGreaterThan(arrivals.count, 2)
    let stale = arrivals
    c.rememberImage(image, for: c.assets[2])
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
    XCTAssertNil(c.transitionImages.object(forKey: c.assets[2].id as NSString))
    XCTAssertNil(c.transitionSmallImages.object(forKey: c.assets[2].id as NSString))
    stale.forEach { $0(image, false) }
    for asset in c.assets {
      XCTAssertNil(c.transitionImages.object(forKey: asset.id as NSString))
      XCTAssertNil(c.transitionSmallImages.object(forKey: asset.id as NSString))
    }
    XCTAssertNil(cell.image.image)
    var fresh = false
    let freshCancel = c.denseCanvas.request(1, 64) { incoming in fresh = incoming === image }
    arrivals.last?(image, false)
    XCTAssertTrue(fresh)
    XCTAssertTrue(c.transitionImages.object(forKey: c.assets[1].id as NSString) === image)
    XCTAssertTrue(c.transitionSmallImages.object(forKey: c.assets[1].id as NSString) === image)
    denseCancel?(); freshCancel?()
  }

  @MainActor func testClearAndRevisionChangeRejectLateStageDeliveryWhileRetainingHeldPixels() throws {
    let c = controller(1)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { _ in }
    let held = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in }
    var arrivals: [(UIImage?, Bool) -> Void] = []
    c.requestImage = { _, _, done in arrivals.append(done); return {} }
    let tile = CalendarZoomStage.Tile()
    tile.display(held)
    let cancel = c.stageTile(tile.photo, asset: 0, pixels: 512)
    let oldRevision = try XCTUnwrap(arrivals.last)
    c.assets[0].revision += 1
    oldRevision(image, false)
    XCTAssertTrue(tile.presentedImage === held)
    let second = c.stageTile(tile.photo, asset: 0, pixels: 512)
    let oldEpoch = try XCTUnwrap(arrivals.last)
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
    oldEpoch(image, false)
    XCTAssertTrue(tile.presentedImage === held, "Cache removal does not erase the live stage's owned pixels")
    XCTAssertNil(c.transitionImages.object(forKey: c.assets[0].id as NSString))
    let fresh = c.stageTile(tile.photo, asset: 0, pixels: 512)
    arrivals.last?(image, false)
    XCTAssertTrue(tile.presentedImage === image)
    XCTAssertTrue(c.transitionImages.object(forKey: c.assets[0].id as NSString) === image)
    cancel?(); second?(); fresh?()
  }

  @MainActor func testMediaPosterReplacementKeepsAssetFittedRectangle() {
    let media = MediaZoomScroll(frame: CGRect(x: 0,y: 0,width: 390,height: 650))
    media.mediaSize = CGSize(width: 3024,height: 4032)
    media.photo.image = UIGraphicsImageRenderer(size: CGSize(width: 128,height: 128)).image { _ in }
    media.layoutIfNeeded()
    let original = media.media.frame, originalInset = media.contentInset
    media.photo.image = UIGraphicsImageRenderer(size: CGSize(width: 600,height: 800)).image { _ in }
    media.setNeedsLayout(); media.layoutIfNeeded()
    XCTAssertEqual(media.media.frame,original,"The cropped grid poster cannot determine the detail aspect ratio")
    XCTAssertEqual(media.contentInset,originalInset)
    XCTAssertEqual(media.media.bounds.width/media.media.bounds.height,0.75,accuracy: 0.001)
    media.media.transform = CGAffineTransform(translationX: 30,y: 80).scaledBy(x: 0.92,y: 0.92)
    XCTAssertEqual(media.frame,CGRect(x: 0,y: 0,width: 390,height: 650),"Only media moves; the letterboxed viewport stays fixed")
    XCTAssertEqual(media.media.transform.ty,80)
  }
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
      XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(), Array(assets.indices))
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
  func testMonthSamplingCapsCoversAndRetainsEveryDayMember() {
    let calendar = Calendar(identifier:.gregorian)
    let assets = (0..<62).map { i in CalendarGridAsset(id:"day-\(i)",
      date:calendar.date(from:DateComponents(year:2026,month:1+6*(i/31),day:1+i%31)),aspect:1) }
    let g = CalendarGridGeometry(assets:assets,level:.months,width:402,columns:3,originalAspect:false)
    XCTAssertEqual(g.tiles.count,12)
    XCTAssertEqual(g.headings.count,2)
    XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(),Array(assets.indices))
    XCTAssertTrue(g.tiles.allSatisfy { $0.members.contains($0.asset) })
    XCTAssertTrue(g.tiles.contains { $0.members.contains(61) })
  }
  @MainActor func testPeriodButtonsAdoptDestinationSizeBeforeLatestAnchor() {
    let c = CalendarGridController()
    let calendar = Calendar(identifier:.gregorian)
    c.assets = (0..<7000).map { i in CalendarGridAsset(id:"day-\(i)",
      date:calendar.date(byAdding:.day,value:i,to:Date(timeIntervalSince1970:1200000000)),aspect:1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    for level in [CalendarGridLevel.months,.years,.all,.years] {
      c.changeLevel(level,asset:6990,from:nil)
      settle(c)
      let tile = c.layout.geometry.tiles.firstIndex { $0.members.contains(6990) }!
      let frame = c.layout.frame(tile).offsetBy(dx:0,dy:-c.grid.contentOffset.y)
      XCTAssertTrue(frame.intersects(c.grid.frame),"Period controls keep the recent photo's period visible")
      XCTAssertGreaterThan(c.grid.contentOffset.y,1000)
      XCTAssertEqual(c.grid.contentSize.height,c.layout.geometry.height,accuracy:0.1)
    }
  }
  @MainActor func testButtonChainKeepsItsFocalPhotoWhenYearCardsCannotCenterAtEnd() {
    let c = CalendarGridController()
    c.assets = (0..<55000).map { i in CalendarGridAsset(id:"photo-\(i)",
      date:Date(timeIntervalSince1970:1577836800+Double(i)*2700),aspect:1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    let focal = c.focusedAsset()
    c.dock.selectedSegmentIndex = CalendarGridLevel.months.rawValue; c.levelChosen()
    settle(c)
    XCTAssertEqual(c.focusedAsset(),focal)
    c.dock.selectedSegmentIndex = CalendarGridLevel.years.rawValue; c.levelChosen()
    settle(c)
    XCTAssertEqual(c.focusedAsset(),focal,"End-clamped year cards must not replace the navigation context with the previous year")
    c.dock.selectedSegmentIndex = CalendarGridLevel.all.rawValue; c.levelChosen()
    settle(c)
    XCTAssertTrue(c.grid.indexPathsForVisibleItems.contains { c.layout.geometry.tiles[$0.item].asset > 54000 })
  }
  @MainActor func testLoadingHeaderAdoptsMediaContrastWithoutWaitingForResize() {
    let c = CalendarGridController(); c.loadViewIfNeeded()
    c.view.frame = CGRect(x:0,y:0,width:402,height:874); c.view.layoutIfNeeded()
    c.replaceAssets((0..<90).map { CalendarGridAsset(id:"photo-\($0)",date:nil,aspect:1) })
    XCTAssertEqual(c.titleLabel.textColor,UIColor.white)
    XCTAssertEqual(c.subtitleLabel.textColor,UIColor.white.withAlphaComponent(0.92))
    c.view.layoutIfNeeded()
    XCTAssertEqual(c.subtitleLabel.frame.minX,c.titleLabel.convert(c.titleLabel.bounds,to:c.view).minX,accuracy:0.1)
  }
  @MainActor func testShortViewKeepsCanvasContrastBehindTheHeader() {
    // A backup view with a few photos leaves the canvas behind the header (design/library.md).
    let c = CalendarGridController(); c.loadViewIfNeeded()
    c.view.frame = CGRect(x:0,y:0,width:402,height:874); c.view.layoutIfNeeded()
    c.replaceAssets([CalendarGridAsset(id:"photo",date:nil,aspect:1)])
    XCTAssertNotEqual(c.titleLabel.textColor,UIColor.white)
    XCTAssertFalse(c.photosBehindHeader)
  }
  func testDensityChangesKeepIdentityAndOriginalAspectDoesNotChangeMembership() {
    let assets = (0..<900).map {
      CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: $0 % 2 == 0 ? 0.7 : 1.8)
    }
    for columns in [1, 3, 5, 15, 31] {
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
  @MainActor func testSelectionMarksOnlySelectedMediaAndKeepsZeroPromptCompact() {
    let cell = CalendarGridCell(frame: CGRect(x: 0, y: 0, width: 130, height: 130))
    cell.selection(false, enabled: true)
    XCTAssertTrue(cell.check.isHidden)
    cell.selection(true, enabled: true)
    XCTAssertFalse(cell.check.isHidden)
    cell.selection(true, enabled: false)
    XCTAssertTrue(cell.check.isHidden)
    let controls = CalendarSelectionControls(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
    controls.countButton.setTitle("Select Items", for: .normal)
    controls.layoutIfNeeded()
    XCTAssertLessThan(controls.countButton.frame.width, 300)
    XCTAssertEqual(controls.countButton.frame.midX, 201)
  }
  /// The live stage settles on a display link; tests finish it directly.
  @MainActor private func finishStage(_ c: CalendarGridController, cancelled: Bool = false) {
    c.finishStage(cancelled: cancelled)
    if c.stage != nil { c.completeStage() }
  }
  @MainActor private func controller(_ count: Int, image: UIImage? = nil) -> CalendarGridController {
    let c = CalendarGridController()
    c.assets = (0..<count).map { CalendarGridAsset(id: "photo-\($0)", date: nil, aspect: 1) }
    if let image { c.requestImage = { _, _, done in done(image, false); return {} } }
    c.loadViewIfNeeded()
    c.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    c.view.setNeedsLayout()
    c.view.layoutIfNeeded()
    return c
  }
  @MainActor func testStageReleaseAdoptsCollectionOnlyAfterSettle() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(300, image: image)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 200)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, 5, "A third of the way toward five columns previews them")
    XCTAssertEqual(c.columns, 3, "The collection keeps its density while fingers are down")
    c.finishStage(cancelled: false)
    XCTAssertEqual(c.columns, 3, "The collection is adopted when the settle ends")
    c.completeStage()
    XCTAssertEqual(c.columns, 5)
    XCTAssertNil(c.stage)
    XCTAssertTrue(c.grid.panGestureRecognizer.isEnabled)
    XCTAssertTrue(c.grid.visibleCells.allSatisfy { ($0 as? CalendarGridCell)?.image.image === image })
  }
  @MainActor func testStageKeepsFocalPhotoInMidLibrary() throws {
    for (distance, expected) in [(CGFloat(420), 1), (CGFloat(240), 5)] {
      let c = controller(10000)
      c.place(c.clampedOffset(60000))
      let point = CGPoint(x: 201, y: c.grid.contentOffset.y + 400)
      c.beginStage(point: point, item: nil, distance: 300)
      let photo = c.pinchTrack.asset
      c.updateStage(distance: distance)
      finishStage(c)
      XCTAssertEqual(c.columns, expected)
      let tile = try XCTUnwrap(c.layout.geometry.tiles.firstIndex { $0.asset == photo })
      let f = c.layout.frame(tile)
      XCTAssertEqual(f.minY + f.height * c.anchorFraction.y - c.grid.contentOffset.y, 400, accuracy: 1)
      XCTAssertGreaterThan(c.grid.contentOffset.y, 10000, "Release never scrolls toward the oldest edge")
    }
  }
  @MainActor func testShortPinchInsideDeadZoneStepsOneStopLikeAButton() {
    let c = controller(1000)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 288)
    XCTAssertEqual(c.stage?.pitch, c.stopPitch(3), "The dead zone shows no scale")
    finishStage(c)
    XCTAssertEqual(c.columns, 5)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 302)
    finishStage(c)
    XCTAssertEqual(c.columns, 5, "Incidental finger movement does not change density")
  }

  @MainActor func testSnapshotPaintsResolvedImagesBeforeHiddenLayersCommit() throws {
    let c = CalendarGridController()
    c.assets = (0..<100).map { CalendarGridAsset(id:"asset-\($0)",date:nil,aspect:1) }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let green = UIGraphicsImageRenderer(size:CGSize(width:64,height:64),format:format).image { ctx in
      UIColor.green.setFill(); ctx.fill(CGRect(x:0,y:0,width:64,height:64))
    }
    c.requestImage = { _,_,done in done(green,false); return {} }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    for case let cell as CalendarGridCell in c.grid.visibleCells {
      cell.image.layer.contents = nil
      XCTAssertNotNil(cell.image.image)
    }
    let image = c.sceneImage().cgImage!, bytes = image.dataProvider!.data! as Data
    let offset = image.height/2*image.bytesPerRow+image.width/2*4
    XCTAssertGreaterThan(bytes[offset+1],240,"Snapshot pixels do not depend on a hidden view's pending layer display")
    XCTAssertLessThan(bytes[offset],15)
    c.stopMotion()
  }

  func testMonthMosaicsCoverOneThroughSixAndMirrorWithoutOverlap() {
    let calendar = Calendar(identifier: .gregorian)
    for month in [1, 2] {
      for count in 1...31 {
        let assets = (1...count).map { day in
          CalendarGridAsset(
            id: "day-\(day)",
            date: calendar.date(from: DateComponents(year: 2026, month: month, day: day)), aspect: 1
          )
        }
        let g = CalendarGridGeometry(
          assets: assets, level: .months, width: 402, columns: 3, originalAspect: false)
        XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(), Array(assets.indices))
        for (i, tile) in g.tiles.enumerated() {
          XCTAssertGreaterThanOrEqual(tile.frame.minX, 19.999)
          XCTAssertLessThanOrEqual(tile.frame.maxX, 382.1)
          for other in g.tiles.dropFirst(i + 1) {
            XCTAssertFalse(tile.frame.intersects(other.frame))
          }
        }
        if count == 2 {
          XCTAssertEqual(g.tiles[0].frame.height / g.tiles[0].frame.width, 4.0 / 3, accuracy: 0.01)
        }
        if count == 3 {
          let hero = g.tiles.max { $0.frame.width < $1.frame.width }!
          XCTAssertEqual(hero.asset, month == 1 ? 0 : 2)
        }
      }
    }
  }
  @MainActor func testDensePeriodCaptionsAvoidOverlapAtShortBoundaries() {
    let assets = (0..<100).map { i in
      CalendarGridAsset(
        id: "year-\(i)",
        date: Calendar.current.date(from: DateComponents(year: 2000 + i / 5, month: 1, day: 1)),
        aspect: 1)
    }
    let layout = CalendarGridLayout()
    layout.geometry = CalendarGridGeometry(
      assets: assets, level: .all, width: 402, columns: 31, originalAspect: false)
    let grid = UICollectionView(
      frame: CGRect(x: 0, y: 0, width: 402, height: 874), collectionViewLayout: layout)
    _ = grid
    let captions = layout.visibleHeadings(in: CGRect(x: 0, y: 0, width: 402, height: 874))
      .compactMap { layout.heading($0)?.frame }
    for i in 1..<captions.count {
      XCTAssertGreaterThanOrEqual(captions[i].minY, captions[i - 1].maxY + 10)
    }
    XCTAssertLessThan(captions.count, layout.geometry.headings.count)
  }
  @MainActor func testHeldPinchCrossesSeveralStopsAndReversesAroundOneAsset() throws {
    let c = controller(500)
    let offset = c.grid.contentOffset
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    let photo = c.pinchTrack.asset
    c.updateStage(distance: 30)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, c.columnStops.last)
    XCTAssertEqual(c.pinchTrack.asset, photo)
    c.updateStage(distance: 261)
    XCTAssertEqual(stage.shownColumns, 3)
    XCTAssertLessThanOrEqual(stage.faces.count, 5)
    finishStage(c, cancelled: true)
    XCTAssertEqual(c.columns, 3)
    XCTAssertEqual(c.grid.contentOffset, offset)
    XCTAssertNil(c.stage)
    XCTAssertEqual(c.columnStops.last, 31, "The year overview is the terminal zoom level")
  }
  @MainActor func testStageReleasePreservesPreviewIncludingFartherStops() {
    let c = controller(500)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 240)
    finishStage(c)
    XCTAssertEqual(c.columns, 5, "Visible progress commits the adjacent stop")
    let d = controller(500)
    d.beginStage(point: CGPoint(x: 201, y: d.grid.contentOffset.y + 437), item: nil, distance: 300)
    d.updateStage(distance: 110)
    XCTAssertEqual(d.stage?.shownColumns, 15)
    finishStage(d)
    XCTAssertEqual(d.columns, 15, "Release keeps the preview even when five is nearer in size")
  }

  @MainActor func testHeldPreviewReversesWithoutReturningToSourceSize() throws {
    let c = controller(10000)
    c.density(columns: 5, at: 5000); c.completeStage()
    c.place(c.clampedOffset(20000))
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    c.updateStage(distance: 339 * 1.45)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, 3)
    c.updateStage(distance: 339 * 1.42)
    XCTAssertEqual(stage.shownColumns, 5, "A small reversal changes photos while tiles remain enlarged")
    XCTAssertEqual(c.pinchTrack.headerColumns, 3, "The date density remains independent of the mixture")
    XCTAssertGreaterThan(stage.pitch, c.stopPitch(5) * 1.4)
    finishStage(c)
    XCTAssertEqual(c.columns, 5, "Release follows the reversed preview rather than nearest size")
  }

  @MainActor func testHeldOverviewReversesAndReturnsWithoutLifting() throws {
    let c = controller(10000)
    c.density(columns: 5, at: 5000); c.completeStage()
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    c.updateStage(distance: 261 * 0.82)
    let stage = try XCTUnwrap(c.stage)
    let photo = c.pinchTrack.asset
    XCTAssertEqual(stage.shownColumns, 15)
    c.updateStage(distance: 261 * 0.84)
    XCTAssertEqual(stage.shownColumns, 5)
    c.updateStage(distance: 261 * 0.82)
    XCTAssertEqual(stage.shownColumns, 15)
    XCTAssertEqual(c.pinchTrack.asset, photo)
    finishStage(c)
    XCTAssertEqual(c.columns, 15)
  }

  @MainActor func testNewestBoundaryIsConstrainedBeforeRelease() throws {
    let c = controller(10000)
    let offset = c.grid.contentOffset
    c.beginStage(point: CGPoint(x: 201, y: offset.y + 400), item: nil, distance: 300)
    c.updateStage(distance: 220)
    let stage = try XCTUnwrap(c.stage)
    let bottom = stage.bounds.height - c.gridInsets(showsInterval: true).bottom
    XCTAssertEqual(stage.focus.y + c.pinchTrack.boundaryDistance * stage.pitch, bottom, accuracy: 0.5)
    XCTAssertGreaterThan(stage.focus.y, c.pinchTrack.startFocus.y)
    XCTAssertEqual(c.grid.contentOffset, offset, "Held motion belongs to the live stage")
    finishStage(c, cancelled: true)
    XCTAssertEqual(c.grid.contentOffset, offset, "Cancellation restores the original scroll offset")
  }

  @MainActor func testPartialFadeReversalPreservesCompositeAndContinuesDuringHold() throws {
    let c = controller(300)
    let stage = CalendarZoomStage(frame: c.grid.frame, columns: 5, pitch: c.stopPitch(5),
      focus: CGPoint(x: 201, y: 400), displayScale: 1)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
      UIColor.systemYellow.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    stage.configureTile = { layer, _, _ in layer.contents = image.cgImage; return nil }
    for count in [5, 3] {
      stage.addFace(columns: count, geometry: c.allGeometry(count), focus: .zero,
        pitch: c.stopPitch(count), opacity: count == 5 ? 1 : 0)
    }
    stage.show(3, animated: true, at: 10)
    stage.advance(to: 10.6)
    let face = try XCTUnwrap(stage.faces[3])
    let weight = face.opacity, alpha = face.container.opacity
    XCTAssertGreaterThan(weight, 0.1); XCTAssertLessThan(weight, 0.9)
    stage.show(5, animated: true, at: 10.6)
    XCTAssertEqual(face.opacity, weight, accuracy: 0.0001)
    let fade = try XCTUnwrap(face.container.animation(forKey: "fade") as? CAKeyframeAnimation)
    XCTAssertEqual((fade.values?.first as? NSNumber)?.floatValue ?? -1, alpha, accuracy: 0.0001,
      "Reversal continues from the blended composite and never reorders the layers")
    let pitch = stage.pitch
    stage.advance(to: 10.9)
    XCTAssertLessThan(face.opacity, weight, "The fade continues with no new finger input")
    XCTAssertEqual(stage.pitch, pitch)
    XCTAssertEqual(stage.faces.values.reduce(0) { $0 + $1.opacity }, 1, accuracy: 0.0001)
    stage.stop()
  }

  @MainActor func testSelectionKeepsHierarchyAndPinchInputOwnership() {
    let c = CalendarGridController(); c.assets = (0..<60).map { CalendarGridAsset(id: "photo-\($0)",date: nil,aspect: 1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x: 0,y: 0,width: 402,height: 874); c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    c.level = .months; c.toggleSelection()
    XCTAssertEqual(c.level,.months); XCTAssertTrue(c.selecting)
    c.level = .all; c.columns = 31; c.toggleSelection(); c.toggleSelection()
    XCTAssertEqual(c.columns,31); XCTAssertTrue(c.selecting)
    XCTAssertTrue(c.gestureRecognizerShouldBegin(UIPinchGestureRecognizer()))
    c.density(columns: 5,at: 30); if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns,5); XCTAssertTrue(c.selecting)
  }

  @MainActor func testScaledFaceFillsBothSidesWithChronologicalNeighbors() throws {
    let c = controller(10000)
    c.place(40000)
    c.beginStage(point: CGPoint(x: 103, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage)
    let face = try XCTUnwrap(stage.faces[3])
    for ratio: CGFloat in [0.65, 0.4] {
      stage.pitch = face.pitch * ratio
      stage.layoutAll()
      let row = try XCTUnwrap(face.tiles.keys.first { key in
        guard let frame = face.tiles[key]?.frame else { return false }
        return frame.minY > 200 && frame.maxY < 700
      }).row
      let tiles = face.tiles.filter { $0.key.row == row }.sorted { $0.value.frame.minX < $1.value.frame.minX }
      XCTAssertLessThanOrEqual(try XCTUnwrap(tiles.first).value.frame.minX, 0)
      XCTAssertGreaterThanOrEqual(try XCTUnwrap(tiles.last).value.frame.maxX, stage.bounds.width)
      for (left, right) in zip(tiles, tiles.dropFirst()) {
        XCTAssertLessThanOrEqual(right.value.frame.minX - left.value.frame.maxX, 2.01)
        let asset = try XCTUnwrap(left.value.photo.name).split(separator: "-").last.flatMap { Int($0) }
        let next = try XCTUnwrap(right.value.photo.name).split(separator: "-").last.flatMap { Int($0) }
        XCTAssertEqual(next, asset.map { $0 + 1 }, "Extended row slots retain chronological identity")
      }
      XCTAssertLessThan(face.tiles.count, 600, "Only the viewport is materialized")
    }
    stage.stop()
  }

  @MainActor func testReleaseKeepsLeadingEdgeAcrossReversalAndCollectionHandoff() throws {
    let c = controller(10000)
    c.place(40000)
    let point = CGPoint(x: 105, y: c.grid.contentOffset.y + 400)
    c.beginStage(point: point, item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage), asset = c.pinchTrack.asset
    c.updateStage(distance: 261 * 0.62)
    let five = try XCTUnwrap(stage.faces[5])
    let phase = five.geometry.leadingSlots
    XCTAssertEqual(phase, 0, "Settled rows start at the leading edge")
    c.updateStage(distance: 261 * 0.64)
    XCTAssertEqual(stage.shownColumns, 3)
    c.updateStage(distance: 261 * 0.62)
    XCTAssertEqual(stage.shownColumns, 5)
    XCTAssertEqual(stage.faces[5]?.geometry.leadingSlots, phase)
    c.finishStage(cancelled: false)
    let now = CACurrentMediaTime()
    for step in 0...120 { stage.advance(to: now + Double(step) / 60) }
    XCTAssertNil(c.stage)
    XCTAssertEqual(c.leadingSlots, phase)
    let f = try XCTUnwrap(c.layout.geometry.tiles.first { $0.asset == asset }).frame
    XCTAssertEqual(f.minY + f.height * c.pinchTrack.fraction.y - c.grid.contentOffset.y, 400, accuracy: 0.25)
  }

  @MainActor func testPrependingOlderAssetsKeepsLeadingEdgeAndVisibleAnchor() throws {
    let c = controller(10000)
    c.place(40000)
    let anchor = try XCTUnwrap(c.browsingAnchor())
    let older = (0..<4).map { CalendarGridAsset(id: "prepended-\($0)", date: nil, aspect: 1) }
    c.replaceAssets(older + c.assets)
    XCTAssertEqual(c.leadingSlots, 0)
    let index = try XCTUnwrap(c.assets.firstIndex(where: { $0.id == anchor.id }))
    let tile = try XCTUnwrap(c.layout.geometry.tiles.firstIndex(where: { $0.members.contains(index) }))
    XCTAssertEqual(c.layout.frame(tile).minY - c.grid.contentOffset.y, anchor.screenY, accuracy: 1)
  }

  @MainActor func testLiveStageUsesNativeDurationLiveSelectionAndStateBadges() throws {
    let c = controller(1000)
    c.assets = c.assets.map { CalendarGridAsset(id: $0.id, date: nil, aspect: 1, videoDuration: "1:23", live: true) }
    c.grid.reloadData(); c.view.layoutIfNeeded()
    c.selected = Set(c.assets.map(\.id)); c.selecting = true
    c.refreshSelection()
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage), face = try XCTUnwrap(stage.faces[3])
    let tile = try XCTUnwrap(face.tiles.values.first), badges = try XCTUnwrap(tile.decorations)
    let cell = CalendarGridCell(frame: tile.bounds)
    cell.duration.text = "1:23"; cell.liveMark.image = UIImage(systemName: "livephoto")
    cell.selection(true, enabled: true); cell.layoutIfNeeded()
    XCTAssertEqual(badges.duration.text, cell.duration.text)
    XCTAssertEqual(badges.duration.isHidden, cell.duration.isHidden)
    XCTAssertTrue(badges.duration.isHidden, "The selection mark replaces the duration")
    XCTAssertFalse(badges.liveMark.isHidden)
    XCTAssertFalse(badges.check.isHidden)
    for (a, b) in [(badges.liveMark.frame, cell.liveMark.frame)] {
      XCTAssertEqual(a.minX, b.minX, accuracy: 0.001); XCTAssertEqual(a.minY, b.minY, accuracy: 0.001)
      XCTAssertEqual(a.width, b.width, accuracy: 0.001); XCTAssertEqual(a.height, b.height, accuracy: 0.001)
    }
    XCTAssertEqual(tile.photo.opacity, Float(cell.image.alpha))
    c.finishStage(cancelled: true); c.completeStage()
    // Media marks (visual-language.md V5): a photo on its way carries a mark;
    // one already in the Pixel's Photos carries none.
    c.selecting = false; c.photoStates = Dictionary(uniqueKeysWithValues: c.assets.map { ($0.id, "sending") })
    c.grid.reloadData(); c.grid.layoutIfNeeded()
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let status = try XCTUnwrap(c.stage?.faces[3]?.tiles.values.first?.decorations)
    XCTAssertFalse(status.stateMark.isHidden); XCTAssertNotNil(status.stateMark.image)
    c.stage?.stop()
  }

  @MainActor func testHeldOverviewFadeDoesNotMoveFocusToFillTargetBottom() throws {
    let c = controller(10000)
    c.density(columns: 5, at: 9999); c.completeStage()
    c.place(.greatestFiniteMagnitude)
    c.beginStage(point: CGPoint(x: 105, y: c.grid.contentOffset.y + 500), item: nil, distance: 300)
    c.updateStage(distance: 210)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, 15)
    let heldFocus = stage.focus
    stage.advance(to: CACurrentMediaTime() + 2)
    XCTAssertEqual(stage.focus, heldFocus, "A held photo crossfade cannot reposition the anchor to fill the incoming face's bottom")
    let face = try XCTUnwrap(stage.faces[15])
    let renderedBottom = stage.focus.y + (face.geometry.height - face.focus.y) * stage.pitch / face.pitch
    let bottom = stage.bounds.height - c.gridInsets(showsInterval: true).bottom
    XCTAssertLessThan(renderedBottom, bottom - 20, "The incoming overview may end above the bottom while fingers are held")
    c.finishStage(cancelled: false)
    let now = CACurrentMediaTime()
    for step in 0...120 { stage.advance(to: now + Double(step) / 60) }
    XCTAssertNil(c.stage)
    XCTAssertEqual(c.grid.contentOffset.y, c.clampedOffset(.greatestFiniteMagnitude), accuracy: 0.5)
  }

  @MainActor func testAdoptionRetainsPresentedPixelsAfterEvictionAndRejectsLateFallback() throws {
    func image(_ edge: CGFloat) -> UIImage {
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      return UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format).image { ctx in
        UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
      }
    }
    let sharp = image(512), small = image(64), fallback = image(40)
    for columns in [5, 15] {
      let c = controller(1000)
      c.requestImage = { _, pixels, done in done(pixels <= 128 ? small : sharp, false); return {} }
      c.place(10000)
      c.density(columns: columns, at: 500)
      let stage = try XCTUnwrap(c.stage), face = try XCTUnwrap(stage.faces[columns])
      stage.show(columns, animated: false)
      stage.pitch = face.pitch
      stage.focus = CGPoint(x: face.focus.x, y: face.focus.y - c.pinchTrack.finalOffset)
      stage.layoutAll()
      let shown = stage.presentations(columns)
      XCTAssertFalse(shown.isEmpty)
      c.transitionImages.removeAllObjects(); c.transitionSmallImages.removeAllObjects()
      var callbacks: [(UIImage?, Bool) -> Void] = []
      c.requestImage = { _, _, done in callbacks.append(done); done(fallback, false); return {} }
      c.completeStage()
      XCTAssertNil(c.stage)
      if columns >= 10 {
        // Dense overviews draw strips from the adopted pixels instead of cells.
        XCTAssertTrue(c.grid.visibleCells.isEmpty)
        XCTAssertFalse(c.denseCanvas.isHidden)
        XCTAssertGreaterThan(c.denseCanvas.layer.sublayers?.count ?? 0, 0)
      } else {
        var compared = 0
        for case let cell as CalendarGridCell in c.grid.visibleCells {
          guard let expected = shown[cell.assetID]?.image else { continue }
          XCTAssertTrue(cell.image.image === expected,
            "The exact displayed image must survive cache eviction and synchronous fallbacks")
          compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
      }
      callbacks.forEach { $0(nil, true); $0(fallback, false) }
      for case let cell as CalendarGridCell in c.grid.visibleCells {
        guard let expected = shown[cell.assetID]?.image else { continue }
        XCTAssertTrue(cell.image.image === expected, "Delayed preview callbacks cannot downgrade adopted pixels")
      }
      XCTAssertTrue(c.adoptingTiles.isEmpty, "Only visible cells retain the handoff pixels")
      c.stopMotion()
      XCTAssertNil(c.adoptionCover)
    }
  }

  @MainActor func testOverviewToOrdinaryGapShowsBackgroundBeforeOutgoingFaceDisappears() throws {
    let c = controller(1000)
    let stage = CalendarZoomStage(frame: c.grid.frame, columns: 15, pitch: c.stopPitch(5),
      focus: CGPoint(x: 201, y: 400), displayScale: 1)
    stage.backgroundColor = .magenta
    let blue = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
      UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    stage.configureTile = { layer, _, _ in layer.contents = blue.cgImage; return nil }
    for count in [15, 5] {
      let g = c.allGeometry(count)
      stage.addFace(columns: count, geometry: g,
        focus: c.stageFocus(g, asset: 500, fraction: CGPoint(x: 0.5, y: 0.5)),
        pitch: c.stopPitch(count), opacity: count == 15 ? 1 : 0)
    }
    stage.show(5, animated: true, at: 10)
    stage.advance(to: 10.8)
    let five = try XCTUnwrap(stage.faces[5]), source = try XCTUnwrap(stage.faces[15])
    XCTAssertGreaterThan(source.opacity, 0)
    XCTAssertLessThan(five.opacity, 1)
    let row = five.tiles.filter { $0.value.frame.midY > 200 && $0.value.frame.midY < 700 }
      .sorted { $0.key.row == $1.key.row ? $0.key.column < $1.key.column : $0.key.row < $1.key.row }
    let left = try XCTUnwrap(row.first { entry in
      let r = entry.value.frame
      return r.minX > 0 && r.maxX < stage.bounds.width - stage.pitch
    })
    let right = try XCTUnwrap(five.tiles[.init(row: left.key.row, column: left.key.column + 1)])
    let point = CGPoint(x: (left.value.frame.maxX + right.frame.minX) / 2, y: left.value.frame.midY)
    XCTAssertGreaterThan(right.frame.minX - left.value.frame.maxX, 1)
    let scale = 4
    let width = Int(stage.bounds.width) * scale, height = Int(stage.bounds.height) * scale
    let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    bitmap.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    stage.layer.render(in: bitmap)
    let data = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
    let offset = (Int(point.y * CGFloat(scale)) * width + Int(point.x * CGFloat(scale))) * 4
    XCTAssertGreaterThan(Int(data[offset]), 220, "The gap reveals magenta background even while the old photo face remains opaque")
    XCTAssertLessThan(Int(data[offset + 1]), 40)
    stage.stop()
  }

  @MainActor func testBadgesScaleWithCellAndDoNotToggleAtDisplayedWidthThreshold() throws {
    let c = controller(1000)
    c.view.frame.size.width = 440; c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    let stage = CalendarZoomStage(frame: c.grid.frame, columns: 5, pitch: c.stopPitch(5),
      focus: CGPoint(x: 220, y: 400), displayScale: 3)
    stage.configureDecorations = { badges, _ in
      badges.duration.text = "1:23"; badges.liveMark.image = UIImage(systemName: "livephoto")
    }
    let g = c.allGeometry(5)
    let face = stage.addFace(columns: 5, geometry: g,
      focus: c.stageFocus(g, asset: 500, fraction: CGPoint(x: 0.5, y: 0.5)),
      pitch: c.stopPitch(5), opacity: 1)
    for ratio: CGFloat in [1.5, 0.7] {
      stage.pitch = face.pitch * ratio; stage.layoutAll()
      let tile = try XCTUnwrap(face.tiles.values.first)
      if let compact = tile.compactDecorations {
        XCTAssertEqual(compact.artwork.state.duration, "1:23")
        XCTAssertNotNil(compact.artwork.state.live)
        let duration = try XCTUnwrap(compact.artwork.marks.first { abs($0.1.width - 61) < 0.01 })
        XCTAssertEqual(compact.layer.convert(duration.1.insetBy(dx: 6, dy: 6), to: tile).width,
          49 * ratio, accuracy: 0.5)
        continue
      }
      let badges = try XCTUnwrap(tile.decorations)
      let duration = badges.layer.convert(badges.duration.frame, to: tile)
      // Tile edges snap to device pixels, so the scale is exact within a pixel.
      XCTAssertEqual(duration.width, 49 * ratio, accuracy: 0.5)
      XCTAssertEqual(badges.layer.convert(badges.liveMark.frame, to: tile).width, 20 * ratio, accuracy: 0.5)
      XCTAssertFalse(badges.duration.isHidden)
      XCTAssertFalse(badges.liveMark.isHidden)
    }
    stage.stop()
  }

  @MainActor func testCompactExpansionDoesNotScheduleReturnToLatest() async throws {
    let c = controller(1000)
    c.active = true; c.place(6000)
    let offset = c.grid.contentOffset
    c.nativeBarCompact = true
    c.nativeBarMorphed(minimized: false)
    let forwarding = CalendarTabReselection(); forwarding.owner = c
    forwarding.returnToLatest(afterExpanding: true)
    try await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertEqual(c.grid.contentOffset, offset)
    XCTAssertFalse(c.scrollingToLatest)
    forwarding.returnToLatest(afterExpanding: false)
    XCTAssertEqual(c.grid.contentOffset.y, c.clampedOffset(.greatestFiniteMagnitude), accuracy: 0.5,
      "Reselecting the expanded Library tab still returns to newest")
  }

  @MainActor func testPinchEntryRetainsNativePixelsWhenTransitionCachesAreEmpty() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320), format: format).image { ctx in
      UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
    }
    let c = controller(1000, image: image)
    let native = Dictionary(uniqueKeysWithValues: c.grid.visibleCells.compactMap { cell -> (String, UIImage)? in
      guard let cell = cell as? CalendarGridCell, let image = cell.image.image else { return nil }
      return (cell.assetID, image)
    })
    XCTAssertFalse(native.isEmpty)
    c.transitionImages.removeAllObjects(); c.transitionSmallImages.removeAllObjects()
    c.requestImage = { _, _, done in done(nil, false); return {} }
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage)
    let shown = stage.presentations(c.columns)
    for (id, image) in native where shown[id] != nil {
      XCTAssertTrue(shown[id]?.image === image, "Entering pinch transfers visible images even when every cache misses")
    }
    XCTAssertTrue(stage.seedTiles.isEmpty, "Face-construction seeds do not accumulate outside visible tile ownership")
    c.stopMotion()
  }


  @MainActor func testDividersFollowShownFaceAndSnapToUniformPixels() throws {
    let c = controller(1000)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage)
    c.updateStage(distance: 240)
    XCTAssertEqual(stage.shownColumns, 5)
    stage.advance(to: CACurrentMediaTime() + 0.05)
    // Mid-crossfade the divider is the shown face's full scaled gap, never a blend.
    XCTAssertEqual(stage.displayedGap, CalendarGridGeometry.gap(columns: 5) * stage.pitch / c.stopPitch(5),
      accuracy: 0.0001)
    for face in stage.faces.values {
      let rows = Dictionary(grouping: face.tiles.values.filter { $0.frame.intersects(stage.bounds) }) {
        Int(($0.frame.minY * stage.displayScale).rounded())
      }
      for row in rows.values {
        let sorted = row.sorted { $0.frame.minX < $1.frame.minX }
        let gaps = zip(sorted, sorted.dropFirst()).map {
          (($1.frame.minX - $0.frame.maxX) * stage.displayScale).rounded()
        }
        XCTAssertLessThanOrEqual(Set(gaps).count, 1, "Every divider in a row has one pixel width")
        for tile in sorted {
          XCTAssertEqual(tile.frame.minX * stage.displayScale, (tile.frame.minX * stage.displayScale).rounded(),
            accuracy: 0.001)
        }
      }
    }
    // Reversing toward the dense overview drops dividers in one step.
    c.updateStage(distance: 120)
    if stage.shownColumns >= 10 { XCTAssertEqual(stage.displayedGap, 0) }
    c.stopMotion()
  }

  @MainActor func testIdenticalLibraryRebuildKeepsPixelsAndPosition() {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(5000, image: image)
    c.place(30000)
    let offset = c.grid.contentOffset
    let cached = c.transitionImages.object(forKey: c.assets[c.layout.geometry.tiles[c.grid.indexPathsForVisibleItems[0].item].asset].id as NSString)
    c.replaceAssets(c.assets)
    XCTAssertEqual(c.grid.contentOffset, offset)
    if let cached {
      let id = c.assets[c.layout.geometry.tiles[c.grid.indexPathsForVisibleItems[0].item].asset].id
      XCTAssertTrue(c.transitionImages.object(forKey: id as NSString) === cached)
    }
  }

  @MainActor func testLibraryChangeWaitsForMotionAndKeepsFocalScreenPosition() throws {
    let c = controller(5000)
    c.place(30000)
    let probe = CGPoint(x: 201, y: c.grid.contentOffset.y + 400)
    let path = try XCTUnwrap(c.grid.indexPathForItem(at: probe))
    let id = c.assets[c.layout.geometry.tiles[path.item].asset].id
    c.beginStage(point: probe, item: nil, distance: 300)
    var values = c.assets
    values.insert(CalendarGridAsset(id: "inserted", date: nil, aspect: 1), at: 2500)
    c.replaceAssets(values)
    XCTAssertEqual(c.assets.count, 5000, "A library change never interrupts a running pinch")
    XCTAssertNotNil(c.pendingAssets)
    c.stopMotion()
    let before = c.grid.convert(c.layout.frame(path.item), to: c.view).minY
    c.replaceAssets(values)
    XCTAssertEqual(c.assets.count, 5001)
    let index = try XCTUnwrap(c.assets.firstIndex { $0.id == id })
    let tile = try XCTUnwrap(c.layout.geometry.tiles.firstIndex { $0.members.contains(index) })
    let after = c.grid.convert(c.layout.frame(tile), to: c.view).minY
    XCTAssertEqual(after, before, accuracy: CalendarGridGeometry.pitch(width: c.width, columns: c.columns),
      "The focused photo stays on screen in the same row band")
  }

  @MainActor func testPrependedHistoryKeepsNewestEdge() {
    let c = controller(1500)
    c.place(c.clampedOffset(.greatestFiniteMagnitude))
    let newestID = c.assets.last?.id
    let older = (0..<4001).map { CalendarGridAsset(id: "older-\($0)", date: nil, aspect: 1) }
    c.replaceAssets(older + c.assets)
    XCTAssertEqual(c.assets.last?.id, newestID)
    XCTAssertEqual(c.layout.frame(0).minX, 0, "The oldest row starts at the leading edge")
    XCTAssertEqual(c.grid.contentOffset.y, c.clampedOffset(.greatestFiniteMagnitude), accuracy: 0.5)
  }

  @MainActor func testLaunchDensityFollowsLastBrowsingDensity() {
    let c = controller(100)
    c.level = .all; c.columns = 1
    XCTAssertEqual(CalendarGridController.rememberedColumns, 3)
    c.columns = 15
    XCTAssertEqual(CalendarGridController.rememberedColumns, 5)
    c.columns = 3
    XCTAssertEqual(CalendarGridController.rememberedColumns, 3)
    c.level = .years
    XCTAssertEqual(CalendarGridController.rememberedColumns, 5)
    XCTAssertEqual(CalendarGridController().columns, 5)
  }

  @MainActor func testDenseOverviewDrawsCanvasWithoutPerPhotoCells() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(6000, image: image)
    c.density(columns: 31, at: nil)
    if c.stage != nil { c.completeStage() }
    c.grid.layoutIfNeeded()
    XCTAssertEqual(c.columns, 31)
    XCTAssertTrue(c.grid.visibleCells.isEmpty, "Dense overviews draw strips, not thousands of cells")
    XCTAssertFalse(c.denseCanvas.isHidden)
    XCTAssertGreaterThan(c.denseCanvas.layer.sublayers?.count ?? 0, 0)
    // Hit testing and pinch anchoring work from geometry alone.
    let point = CGPoint(x: 201, y: c.grid.contentOffset.y + 400)
    let item = try XCTUnwrap(c.item(at: point))
    XCTAssertTrue(c.layout.frame(item).contains(point))
    c.beginStage(point: point, item: nil, distance: 300)
    XCTAssertNotNil(c.stage, "A pinch from the dense overview anchors on a photo")
    c.finishStage(cancelled: true); if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns, 31)
    c.select(item: item)
    if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns, 15, "A tap drills into the month overview")
    XCTAssertTrue(c.grid.visibleCells.isEmpty)
    c.density(columns: 5, at: item)
    if c.stage != nil { c.completeStage() }
    XCTAssertTrue(c.denseCanvas.isHidden)
    XCTAssertFalse(c.grid.visibleCells.isEmpty)
  }

  @MainActor func testZoomMenuStaysOpenAndChainsFromSettlingDensity() throws {
    let c = controller(1000)
    let options = try XCTUnwrap(c.displayMenu().children.compactMap { $0 as? UIMenu }.last)
    let actions = options.children.compactMap { $0 as? UIAction }
    XCTAssertEqual(actions.count, 2)
    XCTAssertTrue(actions.allSatisfy { $0.attributes.contains(.keepsMenuPresented) })
    c.stepDensity(by: 1)
    XCTAssertEqual(c.pinchTrack.target.map { c.columnStops[$0] }, 5)
    c.stepDensity(by: 1)
    XCTAssertEqual(c.pinchTrack.target.map { c.columnStops[$0] }, 15,
      "A repeated tap steps from the density being settled toward")
    if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns, 15)
  }

  @MainActor func testCoverLevelPinchTriggersOneLevelChangeWithoutFollowingFingers() {
    let c = controller(3000)
    c.changeLevel(.years, asset: 2000, from: nil); c.stopMotion()
    let pinch = UIPinchGestureRecognizer()
    pinch.scale = 1.03
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .years, "A pinch below the threshold does nothing")
    pinch.scale = 1.2
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .months, "Pinching out of Years opens Months once")
    c.stopMotion()
    pinch.scale = 2
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .months, "One gesture triggers at most one change")
    c.coverPinchTriggered = false
    pinch.scale = 0.8
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .years)
    c.stopMotion()
  }

  @MainActor func testLaunchSnapshotRoundTripsForTheSameLayout() throws {
    try XCTSkipUnless(CalendarGridController.usesLaunchSnapshot, "The launch cover is disabled")
    CalendarGridController.clearLaunchSnapshot()
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(500, image: image)
    let window = UIWindow(frame: c.view.frame); window.rootViewController = c; window.isHidden = false
    c.view.frame = window.bounds; c.view.layoutIfNeeded()
    c.saveLaunchSnapshot()
    let deadline = Date().addingTimeInterval(2)
    while !FileManager.default.fileExists(atPath: CalendarGridController.launchSnapshotInfoURL.path),
      Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: CalendarGridController.launchSnapshotURL.path))
    let next = CalendarGridController()
    next.loadViewIfNeeded()
    XCTAssertNotNil(next.launchCover, "The next launch shows the snapshot in its first frame")
    next.view.frame = c.view.frame; next.view.setNeedsLayout(); next.view.layoutIfNeeded()
    XCTAssertEqual(next.launchCover?.frame, next.view.bounds)
    next.removeLaunchCover(animated: false)
    XCTAssertNil(next.launchCover)
    CalendarGridController.clearLaunchSnapshot()
    let none = CalendarGridController(); none.loadViewIfNeeded()
    XCTAssertNil(none.launchCover)
    window.isHidden = true
  }
}

@MainActor private final class MediaStripTestSource: NSObject, UICollectionViewDataSource {
  func collectionView(_ view: UICollectionView, numberOfItemsInSection section: Int) -> Int { 55000 }
  func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
    view.dequeueReusableCell(withReuseIdentifier: "tile",for: path)
  }
}
