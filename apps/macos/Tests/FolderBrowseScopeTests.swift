import AppKit
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class FolderBrowseScopeTests: XCTestCase {
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
    XCTAssertEqual(browser.sections.flatMap(\.photos).map(\.folder_id), ["a"])
    browser.scope = .all; await browser.reload(folders)
    XCTAssertEqual(Set(browser.sections.flatMap(\.photos).map(\.folder_id)), ["a", "b"])
    browser.scope = .folder("a")
    XCTAssertEqual(browser.sections.flatMap(\.photos).map(\.folder_id), ["a"])
  }
  func testPagedDepthAndScrollSurviveScopeChanges() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = (0..<150).map { index in
      FolderPhoto(relative: "photo-\(index).jpg", source_id: "\(index)", revision: "1", size: 1,
        media_type: "image/jpeg", modified_ms: 0, folder_id: "a", capture_ms: UInt64(index + 1),
        date_source: "metadata", backup: "not_backed_up", saved_at_ms: nil)
    }
    let browser = FolderBrowser()
    browser.scope = .folder("a"); await browser.reload(folders)
    await browser.more("a", folders: folders)
    XCTAssertEqual(browser.sections.first?.photos.count, 150)
    let savedKey = browser.key
    browser.offsets[savedKey] = CGPoint(x: 0, y: 420)
    browser.scope = .all; await browser.reload(folders)
    browser.scope = .folder("a")
    XCTAssertEqual(browser.sections.first?.photos.count, 150)
    XCTAssertEqual(browser.offsets[browser.key]?.y, 420)
    await browser.reload(folders)
    XCTAssertEqual(browser.sections.first?.photos.count, 150)
  }

  func testEmptyMediaFiltersUseTheSameVisibleMembershipAsTheGrid() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = [photo(0)]
    let browser = FolderBrowser(); browser.scope = .folder("a")
    for type: LibraryFilter in [.burst, .motion, .video] {
      browser.type = type
      XCTAssertEqual(browser.contentState, .loading, "A new filter has not resolved its membership")
      await browser.reload(folders)
      XCTAssertEqual(browser.sections.flatMap(\.photos).count, 1)
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

  func testUnmatchedFirstPageKeepsLoadingUntilALaterMatchingPage() async {
    let folders = FolderSources(backup: BackupModel.shared)
    // Browse returns newest first, so all videos are beyond the first page.
    folders.previewRows = (0..<150).map { photo($0, video: $0 < 50) }
    let browser = FolderBrowser(); browser.scope = .folder("a"); browser.type = .video
    await browser.reload(folders)
    XCTAssertEqual(browser.sections.first?.photos.count, 100)
    XCTAssertTrue(browser.visiblePhotos.isEmpty)
    XCTAssertEqual(browser.contentState, .loading)
    await browser.more("a", folders: folders)
    XCTAssertEqual(browser.contentState, .photos)
    XCTAssertEqual(browser.visiblePhotos.count, 50)
    XCTAssertEqual(MacFolderGridSource(folders: folders, browser: browser).identifiers, browser.visiblePhotos.map(\.id))
  }

  func testUnmatchedPagingFinishesAsFilteredEmptyAndFailureKeepsRecovery() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = (0..<150).map { photo($0) }
    let browser = FolderBrowser(); browser.scope = .folder("a"); browser.type = .burst
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .loading)
    browser.error = "Unable to read folder"
    XCTAssertEqual(browser.contentState, .failed, "A failed page is not a completed empty result")
    browser.error = nil
    await browser.more("a", folders: folders)
    XCTAssertEqual(browser.sections.first?.photos.count, 150)
    XCTAssertEqual(browser.contentState, .filterEmpty)
    browser.type = .all
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .photos)
    folders.previewRows = []
    await browser.reload(folders)
    XCTAssertEqual(browser.contentState, .empty, "An unfiltered empty folder has its own explanation")
  }

  private func photo(_ index: Int, video: Bool = false) -> FolderPhoto {
    FolderPhoto(relative: "photo-\(index).\(video ? "mp4" : "jpg")", source_id: "\(index)", revision: "1", size: 1,
      media_type: video ? "video/mp4" : "image/jpeg", modified_ms: 0, folder_id: "a",
      capture_ms: UInt64(index + 1), date_source: "metadata", backup: "not_backed_up", saved_at_ms: nil)
  }
}
