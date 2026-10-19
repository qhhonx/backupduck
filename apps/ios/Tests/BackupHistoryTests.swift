import XCTest
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
}
