import CoreGraphics
import Foundation
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#elseif canImport(BackupDuck)
@testable import BackupDuck
#endif

final class ThumbnailTableTests: XCTestCase {
  private var directory: URL!
  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("thumbnail-table-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
  private func image(red: Bool) -> CGImage {
    let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
      bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.setFillColor(red: red ? 1 : 0, green: 0, blue: red ? 0 : 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    return context.makeImage()!
  }
  private func assertPixels(_ image: CGImage, red: Bool, file: StaticString = #filePath, line: UInt = #line) {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
      return XCTFail("A retained image must remain readable", file: file, line: line)
    }
    for offset in stride(from: 0, to: image.bytesPerRow * image.height, by: 4) {
      if bytes[offset + (red ? 2 : 0)] < 248 || bytes[offset + (red ? 0 : 2)] > 7 {
        return XCTFail("Retained image pixels changed at byte \(offset)", file: file, line: line)
      }
    }
  }
  func testRetainedDirectImageKeepsPixelsWhenSlotWouldBeReused() throws {
    let table = ThumbnailTable(url: directory.appendingPathComponent("overview-32.table"), side: 32, capacity: 1)
    table.store("red", image: image(red: true))
    try autoreleasepool {
      let held = try XCTUnwrap(table.image("red"))
      table.store("blue", image: image(red: false))
      assertPixels(held, red: true)
      XCTAssertFalse(table.contains("blue"), "A bounded table skips writes when every candidate is leased")
    }
    table.store("blue", image: image(red: false))
    assertPixels(try XCTUnwrap(table.image("blue")), red: false)
  }
  func testRetainedDirectImageKeepsPixelsThroughClearAndRefill() throws {
    let table = ThumbnailTable(url: directory.appendingPathComponent("overview-32.table"), side: 32, capacity: 4)
    table.store("red", image: image(red: true))
    let held = try XCTUnwrap(table.image("red"))
    table.clear()
    XCTAssertFalse(table.contains("red"))
    for index in 0..<40 { table.store("blue-\(index)", image: image(red: false)) }
    assertPixels(held, red: true)
  }
  func testConcurrentDirectReadersRetainTheirRequestedPixelsDuringReuseAndClear() {
    let table = ThumbnailTable(url: directory.appendingPathComponent("overview-32.table"), side: 32, capacity: 8)
    let red = image(red: true), blue = image(red: false)
    DispatchQueue.concurrentPerform(iterations: 300) { index in
      autoreleasepool {
        let key = "asset-\(index)", isRed = index.isMultiple(of: 2)
        table.store(key, image: isRed ? red : blue)
        if let held = table.image(key) {
          if index.isMultiple(of: 7) { table.clear() }
          for rewrite in 0..<4 { table.store("replacement-\(index)-\(rewrite)", image: blue) }
          self.assertPixels(held, red: isRed)
        }
      }
    }
  }
  func testDirectImageOwnsItsMappingAfterTableOwnerIsReleased() throws {
    var table: ThumbnailTable? = ThumbnailTable(url: directory.appendingPathComponent("overview-32.table"), side: 32, capacity: 1)
    table!.store("red", image: image(red: true))
    let held = try XCTUnwrap(table!.image("red"))
    table = nil
    assertPixels(held, red: true)
  }
  func testClearKeepsLeasedPixelsInsideTheTableBudgetUntilReleased() throws {
    let table = ThumbnailTable(url: directory.appendingPathComponent("overview-32.table"), side: 32, capacity: 4)
    table.limit = 1
    table.store("red", image: image(red: true))
    try autoreleasepool {
      let held = try XCTUnwrap(table.image("red"))
      XCTAssertNil(table.clear())
      table.store("blue", image: image(red: false))
      XCTAssertTrue(table.isFull)
      XCTAssertFalse(table.contains("blue"), "Clearing must not create an extra budget for retained pixels")
      XCTAssertGreaterThan(table.usage, 0)
      assertPixels(held, red: true)
    }
    table.writes.sync {}
    XCTAssertEqual(table.usage, 0)
    table.store("blue", image: image(red: false))
    XCTAssertTrue(table.contains("blue"))
  }
  func testASecondOwnerCannotRewriteALeasedMappingWithTheSameGeometry() throws {
    let url = directory.appendingPathComponent("overview-32.table")
    let first = ThumbnailTable(url: url, side: 32, capacity: 1)
    first.store("red", image: image(red: true))
    let held = try XCTUnwrap(first.image("red"))
    let second = ThumbnailTable(url: url, side: 32, capacity: 1)
    second.store("blue", image: image(red: false))
    XCTAssertFalse(second.available, "A busy mapped file falls back to native thumbnails without waiting")
    XCTAssertNil(second.image("blue"))
    assertPixels(held, red: true)
  }
  func testMappingOwnershipEndsAfterTheLastImageReleasesItsLease() throws {
    let url = directory.appendingPathComponent("overview-32.table")
    try autoreleasepool {
      var first: ThumbnailTable? = ThumbnailTable(url: url, side: 32, capacity: 1)
      first!.store("red", image: image(red: true))
      let held = try XCTUnwrap(first!.image("red"))
      first = nil
      let blocked = ThumbnailTable(url: url, side: 32, capacity: 1)
      XCTAssertFalse(blocked.available)
      assertPixels(held, red: true)
    }
    let reopened = ThumbnailTable(url: url, side: 32, capacity: 1)
    XCTAssertTrue(reopened.available)
    assertPixels(try XCTUnwrap(reopened.image("red")), red: true)
  }
  func testBusyMappingsAreMeasuredAndClearReportsTheirOwnership() throws {
    let storage = ThumbnailCacheStorage(directory: directory)
    let url = directory.appendingPathComponent("overview-32.table")
    let first = ThumbnailTable(url: url, side: 32, capacity: 4)
    first.store("red", image: image(red: true))
    let held = try XCTUnwrap(first.image("red"))
    let file = try FileHandle(forWritingTo: url); try file.synchronize(); try file.close()
    let second = ThumbnailTable(url: url, side: 32, capacity: 4, storage: storage)
    XCTAssertFalse(second.available)
    XCTAssertGreaterThan(storage.tableUsage(active: [second]), 0)
    XCTAssertNotNil(storage.clearTables(active: [second]))
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    // An old profile may belong to another active owner too.
    XCTAssertNotNil(storage.clearTables(active: []))
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    assertPixels(held, red: true)
  }
  func testChangedGeometryWaitsForTheOldMappingOwnerWithoutTruncatingPixels() throws {
    let url = directory.appendingPathComponent("overview-32.table")
    try autoreleasepool {
      let old = ThumbnailTable(url: url, side: 48, capacity: 4)
      old.store("red", image: image(red: true))
      let held = try XCTUnwrap(old.image("red"))
      let replacement = ThumbnailTable(url: url, side: 32, capacity: 1)
      XCTAssertFalse(replacement.available)
      replacement.store("blue", image: image(red: false))
      assertPixels(held, red: true)
    }
    let replacement = ThumbnailTable(url: url, side: 32, capacity: 1)
    XCTAssertTrue(replacement.available)
    XCTAssertFalse(replacement.contains("red"))
    replacement.store("blue", image: image(red: false))
    assertPixels(try XCTUnwrap(replacement.image("blue")), red: false)
  }
  func testClearRemovesAnUnopenedManagedTableInsteadOfReportingFalseSuccess() throws {
    let url = directory.appendingPathComponent("overview-32.table")
    try Data(repeating: 1, count: 4096).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
    let storage = ThumbnailCacheStorage(directory: directory)
    let unavailable = ThumbnailTable(url: url, side: 32, capacity: 4, storage: storage)
    XCTAssertFalse(unavailable.available)
    XCTAssertNil(storage.clearTables(active: [unavailable]))
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }
  func testClearReportsADeletionFailureAndRetainsTheFailedFile() throws {
    let storage = ThumbnailCacheStorage(directory: directory)
    let old = directory.appendingPathComponent("overview-48.table")
    try Data(repeating: 1, count: 4096).write(to: old)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
    XCTAssertNotNil(storage.clearTables(active: []))
    XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
  }
  func testDirectoryClearDoesNotFollowASymbolicLink() throws {
    let original = directory.appendingPathComponent("owned", isDirectory: true)
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    let file = original.appendingPathComponent("overview-48.table")
    try Data(repeating: 1, count: 4096).write(to: file)
    let alias = directory.appendingPathComponent("alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
    let storage = ThumbnailCacheStorage(directory: alias)
    XCTAssertNotNil(storage.clearTables(active: []))
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
  }
  func testActiveTableNeverOpensOrClearsThroughASymbolicLinkCacheRoot() throws {
    let original = directory.appendingPathComponent("owned", isDirectory: true)
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    let file = original.appendingPathComponent("overview-32.table")
    autoreleasepool {
      let first = ThumbnailTable(url: file, side: 32, capacity: 4)
      first.store("red", image: image(red: true))
    }
    let originalBytes = try Data(contentsOf: file)
    let alias = directory.appendingPathComponent("alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
    let storage = ThumbnailCacheStorage(directory: alias)
    let throughLink = ThumbnailTable(url: alias.appendingPathComponent("overview-32.table"), side: 32, capacity: 4, storage: storage)
    XCTAssertFalse(throughLink.available)
    XCTAssertNotNil(storage.clearTables(active: [throughLink]))
    XCTAssertEqual(try Data(contentsOf: file), originalBytes)
  }
  func testBlockedDrawingDoesNotBlockEpochOrInvalidationAndCannotPublishOldPixels() throws {
    for clearing in [false, true] {
      let storage = ThumbnailCacheStorage(directory: directory)
      let entered = expectation(description: "Drawing suspended"), invalidated = expectation(description: "Clear or budget intent is immediate")
      let finished = expectation(description: "Old writer completed"), cleaned = expectation(description: "Clear finished")
      let gate = DispatchSemaphore(value: 0)
      let table = ThumbnailTable(url: directory.appendingPathComponent("overview-\(clearing ? 48 : 32).table"),
        side: 32, capacity: 4, storage: storage, render: { context, image, rect in
          entered.fulfill(); _ = gate.wait(timeout: .now() + 5); context.draw(image, in: rect)
        })
      let old = try XCTUnwrap(storage.epoch), red = image(red: true)
      DispatchQueue.global().async {
        table.store("old", image: red, generation: old)
        XCTAssertFalse(table.contains("old"), "An invalidated draw must not publish its slot header")
        finished.fulfill()
      }
      wait(for: [entered], timeout: 2)
      DispatchQueue.global().async {
        XCTAssertEqual(storage.epoch, old, "Reading the epoch must not wait for rasterization")
        if clearing {
          let token = storage.beginClear()!
          invalidated.fulfill()
          XCTAssertNil(storage.clearTables(active: [table])); storage.endClear(token)
        } else {
          storage.invalidate(); invalidated.fulfill()
        }
        cleaned.fulfill()
      }
      wait(for: [invalidated], timeout: 0.5)
      gate.signal()
      wait(for: [finished, cleaned], timeout: 2)
      XCTAssertFalse(table.contains("old"))
    }
  }
  func testClearClosesAdmissionBeforeWaitingForBlockedFilePublication() throws {
    let storage = ThumbnailCacheStorage(directory: directory)
    let epoch = try XCTUnwrap(storage.epoch)
    let file = directory.appendingPathComponent(String(repeating: "a", count: 64) + ".detail")
    let entered = expectation(description: "File publication suspended"), intent = expectation(description: "Clear intent returned")
    let finished = expectation(description: "Clear waited and removed old publication")
    let gate = DispatchSemaphore(value: 0), clearReturned = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      storage.withCurrent(epoch) {
        entered.fulfill(); _ = gate.wait(timeout: .now() + 5)
        try? Data([1, 2, 3]).write(to: file)
      }
    }
    wait(for: [entered], timeout: 2)
    DispatchQueue.global().async {
      XCTAssertEqual(storage.epoch, epoch)
      let clearing = storage.beginClear()!
      intent.fulfill()
      XCTAssertNil(storage.clearDetails())
      storage.endClear(clearing); clearReturned.signal(); finished.fulfill()
    }
    wait(for: [intent], timeout: 0.5)
    XCTAssertEqual(clearReturned.wait(timeout: .now()), .timedOut, "File cleanup waits for already admitted publication")
    gate.signal(); wait(for: [finished], timeout: 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    XCTAssertNil(storage.withCurrent(epoch) { true })
  }
  func testQueuedWritesFromBeforeClearCannotRefillEitherTable() throws {
    let storage = ThumbnailCacheStorage(directory: directory)
    let first = ThumbnailTable(url: directory.appendingPathComponent("overview-32.table"), side: 32, capacity: 4, storage: storage)
    let second = ThumbnailTable(url: directory.appendingPathComponent("detail-48.table"), side: 48, capacity: 4, storage: storage)
    let old = try XCTUnwrap(storage.epoch), red = image(red: true)
    let queue = DispatchQueue(label: "thumbnail-table-test-writer"), gate = DispatchSemaphore(value: 0)
    queue.async {
      gate.wait()
      first.store("late-first", image: red, generation: old)
      second.store("late-second", image: red, generation: old)
    }
    let clearing = try XCTUnwrap(storage.beginClear())
    XCTAssertNil(storage.epoch)
    XCTAssertNil(storage.clearTables(active: [first, second]))
    storage.endClear(clearing)
    gate.signal(); queue.sync {}
    XCTAssertFalse(first.contains("late-first")); XCTAssertFalse(second.contains("late-second"))
    let current = try XCTUnwrap(storage.epoch)
    first.store("new", image: red, generation: current)
    XCTAssertTrue(first.contains("new"))
  }
  func testDirectoryUsageAndClearIncludeOldConfigurationsAndPreserveUnownedFiles() throws {
    let storage = ThumbnailCacheStorage(directory: directory)
    let active = ThumbnailTable(url: directory.appendingPathComponent("overview-32.table"), side: 32, capacity: 4, storage: storage)
    active.store("active", image: image(red: true))
    let old = directory.appendingPathComponent("mac-detail-oldprofile-96.table")
    let foreign = directory.appendingPathComponent("unrelated.table")
    let link = directory.appendingPathComponent("mac-overview-oldprofile-48.table")
    let bytes = Data(repeating: 0x7f, count: 32_768)
    try bytes.write(to: old); try bytes.write(to: foreign)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: foreign)
    XCTAssertGreaterThanOrEqual(storage.tableUsage(active: [active]), active.usage + bytes.count)
    let clearing = try XCTUnwrap(storage.beginClear())
    XCTAssertNil(storage.clearTables(active: [active])); storage.endClear(clearing)
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    XCTAssertEqual(try Data(contentsOf: foreign), bytes)
    XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
    XCTAssertEqual(storage.tableUsage(active: [active]), 0)
  }
}
