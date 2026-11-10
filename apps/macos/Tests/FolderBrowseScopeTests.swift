import AppKit
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class FolderBrowseScopeTests: XCTestCase {
  func testBackupStatusStaysWorkingBetweenFolderTransfers() {
    let restoresNetwork = BackupEnvironment.restoresSenderNetwork
    BackupEnvironment.restoresSenderNetwork = { false }
    defer { BackupEnvironment.restoresSenderNetwork = restoresNetwork }
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    model.pairing = Pairing(version: 1, receiverID: "receiver", endpoint: "", certificate: "", token: "")
    model.ready = true; model.paused = false; model.receiverConnection = .ready
    let folders = FolderSources(backup: model)
    folders.sources = [FolderSource(id: "folder", name: "Fixture", bookmark: Data(),
      automatic: false, enabled: true, receiver: "receiver", lastCheck: nil)]
    folders.phases["folder"] = "folder_preparing"

    model.summary.queued = 1
    let working = folders.hubStatus
    XCTAssertEqual(working, .backingUpWithoutTotal)
    model.summary.queued = 0
    model.summary.received = 1
    XCTAssertEqual(model.hubStatus, .caughtUp(lastSaved: nil, saving: 1), "Reproduce the empty transfer queue between originals")
    XCTAssertEqual(folders.hubStatus, working)
    XCTAssertTrue(MacMenuStatus(model: model, folders: folders).isBackingUp)
    model.summary.running = 1
    XCTAssertEqual(folders.hubStatus, working)
    folders.sources[0].lastCheck = Date()
    folders.sources[0].manualCutoffMS = 123
    XCTAssertEqual(folders.hubDeliveryRequest?.scopes, [.init(source: "folder", cutoff: 123)])
    XCTAssertEqual(FolderDeliveryProgress(delivered: 60, total: 240).fraction, 0.25)
    XCTAssertNil(FolderDeliveryProgress(delivered: 0, total: 0).fraction)
    model.paused = true
    XCTAssertEqual(folders.hubStatus, .paused)
    model.paused = false; model.receiverConnection = .network
    XCTAssertEqual(folders.hubStatus, .problem(.receiverUnreachable))
    model.receiverConnection = .ready
    model.summary.running = 0
    folders.sources[0].receiver = "other-receiver"
    XCTAssertEqual(folders.hubStatus, .caughtUp(lastSaved: nil, saving: 1))
    folders.sources[0].receiver = "receiver"
    folders.phases["folder"] = "folder_up_to_date"
    XCTAssertEqual(folders.hubStatus, .caughtUp(lastSaved: nil, saving: 1))
    XCTAssertFalse(MacMenuStatus(model: model, folders: folders).isBackingUp)
  }

  func testScopesRestoreIndependentSearchFiltersAndSelections() {
    let browser = FolderBrowser()
    browser.search = "camera"
    browser.scope = .folder("a")
    browser.search = "holiday"; browser.filter = .notBackedUp; browser.type = .video
    browser.searchExpanded = true; browser.selection = ["a|one"]
    browser.scope = .folder("b")
    XCTAssertEqual(browser.search, "")
    XCTAssertEqual(browser.filter, .all)
    browser.selection = ["b|two"]
    browser.scope = .folder("a")
    XCTAssertEqual(browser.search, "holiday")
    XCTAssertEqual(browser.filter, .notBackedUp)
    XCTAssertEqual(browser.type, .video)
    XCTAssertTrue(browser.searchExpanded)
    XCTAssertEqual(browser.selection, ["a|one"])
    browser.scope = .all
    XCTAssertEqual(browser.search, "camera")
    browser.scope = .folder("b")
    XCTAssertEqual(browser.selection, ["b|two"])
  }

  func testVisibleDateOwnerReturnsWithItsScope() {
    let browser = FolderBrowser()
    browser.scope = .folder("a")
    let first = browser.visibleRange
    first.title = "January"
    browser.scope = .folder("b")
    XCTAssertFalse(browser.visibleRange === first)
    XCTAssertEqual(browser.visibleRange.title, "")
    browser.visibleRange.title = "February"
    browser.scope = .folder("a")
    XCTAssertTrue(browser.visibleRange === first)
    XCTAssertEqual(browser.visibleRange.title, "January")
    browser.scope = .folder("b")
    XCTAssertEqual(browser.visibleRange.title, "February")
  }

  func testFolderQueryDoesNotMixSources() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = ["a", "b"].map { id in
      FolderPhoto(relative: "photo.jpg", source_id: "photo", revision: "1", size: 1,
        media_type: "image/jpeg", modified_ms: 0, folder_id: id, capture_ms: 1,
        date_source: "metadata", backup: "not_backed_up", saved_at_ms: nil)
    }
    let browser = FolderBrowser()
    browser.scope = .folder("a"); await browser.reload(folders)
    XCTAssertEqual(browser.visiblePhotos.map(\.folder_id), ["a"])
    browser.scope = .all; await browser.reload(folders)
    XCTAssertEqual(Set(browser.visiblePhotos.map(\.folder_id)), ["a", "b"])
    browser.scope = .folder("a")
    XCTAssertEqual(browser.visiblePhotos.map(\.folder_id), ["a"])
  }
  func testFullResultAndScrollSurviveScopeChanges() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = (0..<2_400).map { photo($0, video: $0.isMultiple(of: 2)) }
    let browser = FolderBrowser()
    browser.scope = .folder("a"); await browser.reload(folders)
    XCTAssertEqual(browser.result?.grid.totals, MacGridTotals(total: 2_400, photos: 1_200, videos: 1_200))
    let savedKey = browser.key
    browser.offsets[savedKey] = CGPoint(x: 0, y: 420)
    browser.scope = .all; await browser.reload(folders)
    browser.scope = .folder("a")
    XCTAssertEqual(browser.visiblePhotos.count, 2_400)
    XCTAssertEqual(browser.offsets[browser.key]?.y, 420)
    await browser.reload(folders)
    XCTAssertEqual(browser.visiblePhotos.count, 2_400)
  }

  func testEmptyMediaFiltersUseTheSameVisibleMembershipAsTheGrid() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = [photo(0)]
    let browser = FolderBrowser(); browser.scope = .folder("a")
    for type: LibraryFilter in [.burst, .motion, .video] {
      browser.type = type
      XCTAssertEqual(browser.contentState, .loading, "A new filter has not resolved its membership")
      await browser.reload(folders)
      XCTAssertTrue(browser.visiblePhotos.isEmpty)
      XCTAssertTrue(browser.visiblePhotos.isEmpty)
      XCTAssertTrue(MacFolderGridSource(folders: folders, browser: browser).identifiers.isEmpty)
      XCTAssertEqual(browser.contentState, .filterEmpty, "Raw JPEG rows do not fill a filtered grid")
    }
    browser.search = "photo"; browser.filter = .notBackedUp
    await browser.reload(folders)
    browser.clearFilters()
    XCTAssertEqual(browser.scope, .folder("a"), "Clearing filters must retain the current folder")
    XCTAssertEqual(browser.type, .all)
    XCTAssertEqual(browser.filter, .all)
    XCTAssertEqual(browser.search, "")
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .photos)
    XCTAssertEqual(MacFolderGridSource(folders: folders, browser: browser).identifiers, browser.visiblePhotos.map(\.id))
  }

  func testSparseTypeFilterReturnsCompleteMembership() async {
    let folders = FolderSources(backup: BackupModel.shared)
    // The core returns newest first, so all videos are beyond its first page.
    folders.previewRows = (0..<150).map { photo($0, video: $0 < 50) }
    let browser = FolderBrowser(); browser.scope = .folder("a"); browser.type = .video
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .photos)
    XCTAssertEqual(browser.visiblePhotos.count, 50)
    let result = MacFolderGridSource(folders: folders, browser: browser).fetchResult
    XCTAssertEqual(result.totals, MacGridTotals(total: 50, photos: 0, videos: 50))
    XCTAssertEqual(result.mediaKind(at: 49), .video)
    XCTAssertEqual(MacFolderGridSource(folders: folders, browser: browser).identifiers, browser.visiblePhotos.map(\.id))
  }

  func testEmptyTypeFilterAndFailureKeepDistinctRecovery() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = (0..<150).map { photo($0) }
    let browser = FolderBrowser(); browser.scope = .folder("a"); browser.type = .burst
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .filterEmpty)
    browser.error = "Unable to read folder"
    XCTAssertEqual(browser.contentState, .failed, "A failed query is distinct from an empty result")
    browser.error = nil
    XCTAssertTrue(browser.visiblePhotos.isEmpty)
    XCTAssertEqual(browser.contentState, .filterEmpty)
    browser.type = .all
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .photos)
    folders.previewRows = []
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .empty, "An unfiltered empty folder has its own explanation")
  }

  func testRefetchReplacesMembershipAfterAnInsert() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = (0..<150).map { photo($0) }
    let browser = FolderBrowser()
    browser.scope = .folder("a")
    await browser.reload(folders)
    folders.previewRows?.append(photo(150))
    await browser.reload(folders)
    XCTAssertEqual(browser.identifiers.count, 151)
    XCTAssertEqual(Set(browser.identifiers).count, browser.identifiers.count)
    XCTAssertEqual(browser.identifiers.first, photo(0).id)
    XCTAssertEqual(browser.identifiers.last, photo(150).id)
    XCTAssertTrue(MacFolderGridSource(folders: folders, browser: browser).startsAtEnd)
  }

  private func photo(_ index: Int, video: Bool = false) -> FolderPhoto {
    FolderPhoto(relative: "photo-\(index).\(video ? "mp4" : "jpg")", source_id: "\(index)", revision: "1", size: 1,
      media_type: video ? "video/mp4" : "image/jpeg", modified_ms: 0, folder_id: "a",
      capture_ms: UInt64(index + 1), date_source: "metadata", backup: "not_backed_up", saved_at_ms: nil)
  }
}
