import AppKit
import Photos
import SwiftUI
import XCTest
@testable import BackupDuck

@MainActor final class MacGridTests: XCTestCase {
  func testAspectAvailabilityAtEveryDensityAndPlaceholder() {
    for columns in MacLibraryDensity.grid {
      XCTAssertTrue(MacLibraryDensity.canChangeAspect(level: .all, columns: columns, hasPhotos: true))
    }
    for columns in [12, 14, 20, 40, 80] {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: .all, columns: columns, hasPhotos: true))
    }
    for level in MacLibraryLevel.allCases {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: level, columns: 3, hasPhotos: false))
    }
    for level in [MacLibraryLevel.years, .months] {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: level, columns: 3, hasPhotos: true))
    }
  }

  func testFolderSummaryHeightMatchesLaidOutHostingView() {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = []
    let folder = FolderSource(id: "folder", name: String(repeating: "Long folder name ", count: 8),
      bookmark: Data(), automatic: false, enabled: true, receiver: nil, lastCheck: nil)
    let summary = AnyView(FolderSectionHeader(folders: folders, source: folder, settings: { _ in }, stop: { _ in }))
    var previous: CGFloat = .greatestFiniteMagnitude
    for gridWidth: CGFloat in [320, 460, 760, 1180] {
      let width = MacGridSectionHeader.contentWidth(for: gridWidth)
      let measured = MacGridSectionHeader.fittingHeight(introduction: summary, width: width)
      let header = MacGridSectionHeader(frame: CGRect(x: 2, y: 0, width: width, height: measured))
      header.configure(title: "October 26, 2026", introduction: summary)
      header.layoutSubtreeIfNeeded()
      guard let host = header.summary else { XCTFail("Missing folder summary"); return }
      XCTAssertEqual(host.frame.width, width)
      XCTAssertEqual(host.frame.height, ceil(host.fittingSize.height), accuracy: 1)
      XCTAssertEqual(measured, ceil(host.fittingSize.height) + MacGridSectionHeader.dateHeight, accuracy: 1)
      XCTAssertLessThanOrEqual(measured, previous)
      previous = measured
    }
  }

  func testFirstLayoutDefersHeaderMeasurementUntilViewportHasWidth() async {
    let source = GridTestSource()
    source.introduction = AnyView(Text(String(repeating: "Wrapped folder summary ", count: 20)))
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: .zero)
    let collection = NSCollectionView(frame: .zero)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; coordinator.collection = collection
    coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    XCTAssertTrue(coordinator.dataSource!.snapshot().itemIdentifiers.isEmpty)
    scroll.setFrameSize(NSSize(width: 804, height: 600))
    coordinator.contentResized()
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(coordinator.dataSource!.snapshot().itemIdentifiers, source.identifiers)
    XCTAssertEqual(layout.headerHeights, source.headerHeights(width: scroll.contentSize.width))
    scroll.setFrameSize(NSSize(width: 460, height: 600))
    coordinator.contentResized()
    XCTAssertEqual(layout.headerHeights, source.headerHeights(width: scroll.contentSize.width))
  }

  func testReadOnlyAlbumCannotEnterSelection() {
    let source = GridTestSource()
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4, selecting: false, readOnly: true)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let collection = NSCollectionView(); coordinator.collection = collection
    coordinator.ids = source.identifiers
    coordinator.beginSelection(at: IndexPath(item: 0, section: 0))
    coordinator.toggleSelection(at: IndexPath(item: 0, section: 0))
    XCTAssertTrue(source.selection.isEmpty)
  }

  func testSourceSectionsShareTileGeometryAndPreservePartialRows() {
    let geometry = MacGridGeometry.make(count: 8, groups: [0: "Today", 3: "Yesterday"], columns: 4, width: 804)
    XCTAssertEqual(geometry.headers.map(\.firstItem), [0, 3])
    XCTAssertEqual(geometry.items[0].size, geometry.items[3].size)
    XCTAssertGreaterThan(geometry.items[3].minY, geometry.items[0].maxY)
    XCTAssertEqual(geometry.items[3].minX, geometry.items[0].minX)
    let summary = MacGridGeometry.make(count: 8, groups: [0: "Today", 3: "Yesterday"], columns: 4, width: 804, headerHeights: [0: 150])
    XCTAssertEqual(summary.items[0].minY - geometry.items[0].minY, 106)
    XCTAssertEqual(summary.items[0].width, geometry.items[0].width)
  }

  func testMarkRefreshKeepsNativeCellAndSelection() async {
    let source = GridTestSource()
    let navigation = MacLibraryNavigation()
    let grid = MacMediaGrid(source: source, navigation: navigation, queueRevision: 0, receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 804, height: 600))
    let collection = NSCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; coordinator.collection = collection
    coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(100))
    collection.layoutSubtreeIfNeeded()
    let path = IndexPath(item: 0, section: 0)
    guard let before = collection.item(at: path) as? PhotoCell else { XCTFail("No visible native cell"); return }
    source.mark = "needs_you"; source.selection = ["a"]
    coordinator.applyItems(scroll: scroll, layout: layout)
    XCTAssertTrue(collection.item(at: path) === before, "A mark observation cannot replace the cell")
    XCTAssertEqual(coordinator.dataSource?.snapshot().itemIdentifiers, ["a", "b", "c"])
    XCTAssertEqual(coordinator.selectedPaths(), [path])
    source.identifiers = ["c", "a", "new"]
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(400))
    XCTAssertEqual(coordinator.dataSource?.snapshot().itemIdentifiers, ["c", "a", "new"])
    XCTAssertEqual(coordinator.selectedPaths(), [IndexPath(item: 1, section: 0)])
    XCTAssertEqual(source.selection, ["a"])
  }

  func testHistoryRefreshKeepsLoadedPagesAndSourceIdentity() async {
    let previous = BackupEnvironment.core
    defer { BackupEnvironment.core = previous }
    let core = GridHistoryCore(); BackupEnvironment.core = core
    let model = BackupHistoryModel()
    await model.reload(receiver: "test-receiver")
    await model.loadMore()
    XCTAssertEqual(model.photos.count, 220)
    core.reordered = true
    await model.reload(receiver: "test-receiver")
    XCTAssertEqual(model.photos.count, 220, "Observations must retain the loaded browsing window")
    XCTAssertEqual(model.photos.first?.id, "job-219")
    XCTAssertFalse(model.hasMore)
    let state = MacHistoryGridState()
    let source = MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "")
    XCTAssertEqual(source.identifiers.count, 220)
    XCTAssertEqual(source.identifiers.first, "job-7", "Needs You precedes day groups")
    XCTAssertEqual(source.identifiers.filter { $0 == "job-7" }.count, 1)
    let video = MacHistoryGridSource(history: model, state: state, filter: "all", type: .video, search: "")
    XCTAssertEqual(video.identifiers.count, 110)
    XCTAssertFalse(video.identifiers.contains("job-7"))
    source.scroll.anchor = "job-200"
    XCTAssertEqual(MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "").scroll.anchor, "job-200")
    XCTAssertNil(video.scroll.anchor, "Each browse view owns its anchor")
  }

  func testFolderResizeRetainsDisplayedPixelsUntilReplacementArrives() {
    let cell = PhotoCell()
    let folder = FolderSource(id: "folder", name: "Synthetic", bookmark: Data(), automatic: false,
      enabled: true, receiver: nil, lastCheck: nil)
    let photo = FolderPhoto(relative: "photo.jpg", source_id: "file", revision: "1", size: 100,
      media_type: "image/jpeg", modified_ms: 1000, folder_id: "folder", capture_ms: 1000,
      date_source: "embedded", backup: "not_backed_up", saved_at_ms: nil)
    let image = NSImage(size: NSSize(width: 32, height: 32))
    cell.configureFolder(photo, source: folder, pixels: 100, synthetic: image)
    XCTAssertTrue(cell.displayedImage === image)
    // The deliberately invalid bookmark makes the larger request unavailable.
    cell.configureFolder(photo, source: folder, pixels: 200)
    XCTAssertTrue(cell.displayedImage === image, "Resizing an unchanged file must never blank its cover")
    cell.cancel()
  }

  func testSupplementaryDiffProbesAcceptSectionOnlyPaths() {
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    XCTAssertNil(layout.layoutAttributesForSupplementaryView(ofKind: LibraryTimelineLayout.headerKind, at: IndexPath(index: 0)))
    XCTAssertNil(layout.layoutAttributesForSupplementaryView(ofKind: LibraryTimelineLayout.headerKind, at: IndexPath()))
  }

  func testRegistrationFeedbackExpires() async {
    let action = SelectionBackupAction()
    await action.perform({ true }, failure: { nil })
    XCTAssertTrue(action.added)
    try? await Task.sleep(for: .milliseconds(2150))
    XCTAssertFalse(action.added)
  }
}

@MainActor private final class GridTestSource: MacGridSource {
  var identifiers = ["a", "b", "c"]
  var contextID = "test"
  var contentRevision = "1"
  var selection = Set<String>()
  let scroll = MacGridScrollState()
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  var mark: String?
  var introduction: AnyView?
  var groups: [Int: String] { introduction == nil ? [:] : [0: "Today"] }
  func introduction(at index: Int) -> AnyView? { index == 0 ? introduction : nil }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    introduction.map { [0: MacGridSectionHeader.fittingHeight(introduction: $0,
      width: MacGridSectionHeader.contentWidth(for: width))] } ?? [:]
  }
  func date(_ id: String) -> Date? { nil }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    cell.configureUnavailable(id: id, label: id, video: false)
    cell.setState(mark)
  }
}

private final class GridHistoryCore: CoreTransport, @unchecked Sendable {
  var reordered = false
  func call(_ command: String) async throws -> Data {
    let query = try JSONSerialization.jsonObject(with: Data(command.utf8)) as! [String: Any]
    var ordered = Array(0..<220)
    if reordered { ordered.insert(ordered.removeLast(), at: 0) }
    if query["state"] as? String == "attention" { ordered = [7] }
    let start = (query["after"] as? Int).flatMap { ordered.firstIndex(of: $0).map { $0 + 1 } } ?? 0
    let page = ordered.dropFirst(start).prefix(200)
    let items: [[String: Any]] = page.map { id in
      ["id": "job-\(id)", "cursor": id, "sort_value": 1_792_495_800_000 - id * 1000,
        "job": ["id": id, "receiver_id": "test-receiver", "state": id == 7 ? "failed" : "received",
          "processing": "complete", "confirmed_bytes": 100,
          "asset": ["kind": id % 2 == 0 ? "video" : "photo", "source_id": "source-\(id)", "revision": "1",
            "metadata": ["source_type": id % 3 == 0 ? "folder" : "library"],
            "resources": [["filename": "sample-\(id).jpg", "size": 100]]]]]
    }
    let summary: [String: Any] = ["total": 220, "attention": 1, "received": 219, "published": 219,
      "publication_failed": 0, "waiting": 0, "failed": 1, "queued": 0, "running": 0, "paused": 0, "confirmed_bytes": 21900]
    return try JSONSerialization.data(withJSONObject: ["ok": true, "value": ["items": items, "summary": summary]])
  }
}
