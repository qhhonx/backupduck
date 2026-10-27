import XCTest
import Photos
@testable import BackupDuck

@MainActor final class BackupHistoryTests: XCTestCase {
  private func item(_ id: Int64, state: String, error: String? = nil, processing: String? = nil,
    processingError: String? = nil, changed: Int64 = 1_792_300_000_000) throws -> BackupTaskItem {
    let json: [String: Any] = ["id": "job-\(id)", "cursor": id, "sort_value": changed, "job": [
      "id": id, "state": state, "confirmed_bytes": 0, "error_code": error as Any, "processing": processing as Any,
      "processing_error": processingError as Any, "state_changed_at_ms": changed,
      "asset": ["kind": "photo", "source_id": "s\(id)", "revision": "1", "resources": [["filename": "IMG.HEIC", "size": 10]]]]]
    return try JSONDecoder().decode(BackupTaskItem.self, from: JSONSerialization.data(withJSONObject: json))
  }

  func testMarksSayOnlyWhatIsKnown() throws {
    XCTAssertEqual(HistoryPhoto(try item(1, state: "received", processing: "complete"))?.mark, .saved)
    XCTAssertEqual(HistoryPhoto(try item(2, state: "received", processing: "pending"))?.mark, .saving)
    XCTAssertEqual(HistoryPhoto(try item(3, state: "received"))?.mark, .saving)
    XCTAssertEqual(HistoryPhoto(try item(4, state: "running"))?.mark, .sending)
    XCTAssertEqual(HistoryPhoto(try item(5, state: "failed", error: "integrity"))?.mark, .needsYou)
  }

  func testCausesGroupByWhatTheUserCanDo() throws {
    XCTAssertEqual(HistoryPhoto(try item(1, state: "received", processing: "failed", processingError: "conversion_required"))?.cause, .liveConversion)
    XCTAssertEqual(HistoryPhoto(try item(2, state: "received", processing: "failed"))?.cause, .pixelSave)
    XCTAssertEqual(HistoryPhoto(try item(3, state: "failed", error: "integrity"))?.cause, .incomplete)
    XCTAssertEqual(HistoryPhoto(try item(4, state: "failed", error: "source_unavailable"))?.cause, .originalUnavailable)
    XCTAssertEqual(HistoryPhoto(try item(5, state: "failed", error: "network"))?.cause, .notSent)
    XCTAssertNil(HistoryPhoto(try item(6, state: "received", processing: "complete"))?.cause)
    XCTAssertFalse(HistoryCause.liveConversion.retries)
    XCTAssertFalse(HistoryCause.pixelSave.retries)
    XCTAssertTrue(HistoryCause.incomplete.retries)
  }
  func testOriginalPreparationClassificationAndPrivateContext() {
    for code in [3164, 3201, 3303, 3305] {
      XCTAssertEqual(OriginalPreparationFailure.reason(NSError(domain: PHPhotosErrorDomain, code: code)), "source_unavailable")
    }
    for code in [3169, 3301, 3307] {
      XCTAssertEqual(OriginalPreparationFailure.reason(NSError(domain: PHPhotosErrorDomain, code: code)), "network")
    }
    for code in [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet] {
      XCTAssertEqual(OriginalPreparationFailure.reason(NSError(domain: NSURLErrorDomain, code: code)), "network")
    }
    for code in [3, 4, 6, 7, 23] {
      XCTAssertEqual(OriginalPreparationFailure.reason(NSError(domain: "CKErrorDomain", code: code)), "network")
    }
    for code in [-1, 3302, 3310, 3311] {
      XCTAssertEqual(OriginalPreparationFailure.reason(NSError(domain: PHPhotosErrorDomain, code: code)), "internal")
    }
    let nested = NSError(domain: PHPhotosErrorDomain, code: -1,
      userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)])
    XCTAssertEqual(OriginalPreparationFailure.reason(nested), "network")
    // A missing resource caused by a failing iCloud Photos download is retried.
    let cloud = NSError(domain: PHPhotosErrorDomain, code: 3303,
      userInfo: [NSUnderlyingErrorKey: NSError(domain: "CloudPhotoLibraryErrorDomain", code: 1005)])
    XCTAssertEqual(OriginalPreparationFailure.reason(cloud), "network")
    XCTAssertEqual(OriginalPreparationFailure.context(cloud)["underlying_code"] as? Int, 1005)
    let error = NSError(domain: PHPhotosErrorDomain, code: 3303,
      userInfo: [NSLocalizedDescriptionKey: "private filename", NSFilePathErrorKey: "/private/photo.heic"])
    let context = OriginalPreparationFailure.context(error)
    XCTAssertEqual(context["error_domain"] as? String, PHPhotosErrorDomain)
    XCTAssertEqual(context["error_code"] as? Int, 3303)
    XCTAssertEqual(context["photos_error"] as? String, "missingResource")
    XCTAssertEqual(Set(context.keys), ["error_domain", "error_code", "photos_error"])
    XCTAssertEqual(OriginalPreparationFailure.reason(Bridge.Failure(code: "local_free_space")), "local_free_space")
  }

  func testPreparationCausesDoNotCallEveryFailureAMissingOriginal() throws {
    func preparation(_ error: String) throws -> HistoryPhoto? {
      let json = "{\"id\":\"preparation:one\",\"cursor\":-1,\"preparation\":{\"cursor\":-1,\"request_id\":\"one\",\"source\":\"one\",\"revision\":\"1\",\"state\":\"preparing\",\"retry_at\":300,\"error_code\":\"\(error)\"}}"
      return HistoryPhoto(try JSONDecoder().decode(BackupTaskItem.self, from: Data(json.utf8)))
    }
    XCTAssertEqual(try preparation("network")?.mark, .sending)
    XCTAssertNil(try preparation("network")?.cause)
    XCTAssertEqual(try preparation("source_unavailable")?.cause, .originalUnavailable)
    XCTAssertEqual(try preparation("internal")?.cause, .notSent)
    // Retry reaches a photo that has no transfer yet through its preparation.
    XCTAssertEqual(try preparation("source_unavailable")?.preparationRequest, "one")
    XCTAssertFalse(BackupModel.sourceRemoved("folder-file-1"), "Only Photos identifiers can be judged deleted")
  }

  func testEmptyBackupViewsAreNotPhotoAccessFailuresAndResetBothFilters() async {
    let original = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = original }
    for access in [PHAuthorizationStatus.authorized, .limited] {
      let library = PhotoLibraryModel()
      library.installSyntheticAssets(EmptyPreparationTestAssets(), filter: .video, backupView: .notBackedUp, access: access)
      guard case .filterEmpty? = library.placeholder else { XCTFail("Expected filter results placeholder"); continue }
      library.selection = ["selected"]
      await library.resetFilters()
      XCTAssertEqual(library.filter, .all)
      XCTAssertEqual(library.backupView, .all)
      XCTAssertTrue(library.selection.isEmpty)
      guard case .empty(filtered: false)? = library.placeholder else { XCTFail("Real empty library retains its placeholder"); continue }
    }
  }

}

private final class EmptyPreparationTestAssets: PHFetchResult<PHAsset>, @unchecked Sendable {
  override var count: Int { 0 }
}
