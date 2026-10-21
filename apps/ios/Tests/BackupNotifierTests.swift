import XCTest
@testable import BackupDuck

@MainActor final class BackupNotifierTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 100_000)
  private func changes(_ status: BackupHubStatus, _ memory: inout BackupNotifier.Memory,
    after: TimeInterval = 0, allowed: Bool = true, connection: ReceiverConnection = .ready,
    earlier: HistoricalImportStatus? = nil) -> [BackupNotifier.Change] {
    BackupNotifier.changes(status: status, earlier: earlier, connection: connection,
      now: now.addingTimeInterval(after), allowed: allowed, memory: &memory)
  }
  func testOfflineNeedsADayAndAFreshObservationThenRecoveryWithdraws() {
    var memory = BackupNotifier.Memory()
    let offline = BackupHubStatus.problem(.receiverUnreachable)
    XCTAssertEqual(changes(offline, &memory, connection: .network), [])
    XCTAssertEqual(changes(offline, &memory, after: 86_399, connection: .network), [])
    XCTAssertEqual(changes(offline, &memory, after: 86_400, connection: .network), [.post(.unreachable)])
    XCTAssertEqual(changes(offline, &memory, after: 86_500, connection: .network), [])
    XCTAssertEqual(changes(.opening, &memory, connection: .unknown), [])
    XCTAssertEqual(changes(.empty, &memory), [.withdraw(.unreachable)])
    XCTAssertNil(memory.unreachableSince)
  }
  func testPauseAndPermissionDoNotProduceStaleReminders() {
    var memory = BackupNotifier.Memory()
    let offline = BackupHubStatus.problem(.receiverUnreachable)
    _ = changes(offline, &memory, connection: .network)
    XCTAssertEqual(changes(offline, &memory, after: 90_000, allowed: false, connection: .network), [])
    XCTAssertFalse(memory.unreachableNotified)
    XCTAssertEqual(changes(.paused, &memory, connection: .network), [.withdraw(.unreachable)])
    XCTAssertEqual(changes(offline, &memory, after: 100_000, connection: .network), [])
  }
  func testFullAndConversionRecoverRearmAndRetryFailedDelivery() {
    var memory = BackupNotifier.Memory()
    XCTAssertEqual(changes(.problem(.receiverFull), &memory, allowed: false), [])
    XCTAssertEqual(changes(.problem(.receiverFull), &memory), [.post(.full)])
    XCTAssertEqual(changes(.problem(.receiverFull), &memory), [])
    memory.retry(.full)
    XCTAssertEqual(changes(.problem(.receiverFull), &memory), [.post(.full)])
    XCTAssertEqual(changes(.problem(.conversionNeeded(2)), &memory), [.withdraw(.full), .post(.convert)])
    XCTAssertEqual(changes(.problem(.conversionNeeded(2)), &memory), [])
    XCTAssertEqual(changes(.problem(.conversionNeeded(3)), &memory), [.post(.convert)])
    XCTAssertEqual(changes(.empty, &memory), [.withdraw(.convert)])
  }
  func testEarlierWaitsForPublicationAndTracksRunIdentity() {
    var memory = BackupNotifier.Memory()
    func history(_ run: Int64, _ published: Int?) -> HistoricalImportStatus {
      HistoricalImportStatus(run: run, state: "scanned", checked: 10, pending: 0, published: published)
    }
    XCTAssertEqual(changes(.empty, &memory, earlier: history(1, 10)), [.withdraw(.earlier)])
    // A different run re-arms; preparation and receipt never finish it.
    XCTAssertEqual(changes(.empty, &memory, earlier: history(2, nil)), [.withdraw(.earlier)])
    XCTAssertEqual(changes(.empty, &memory, earlier: history(2, 0)), [])
    XCTAssertEqual(changes(.empty, &memory, earlier: history(2, 9)), [])
    XCTAssertEqual(changes(.empty, &memory, earlier: history(2, 10)), [.post(.earlier)])
    XCTAssertEqual(changes(.empty, &memory, earlier: history(2, 10)), [])
    let data = try! JSONEncoder().encode(memory)
    let resumed = try! JSONDecoder().decode(BackupNotifier.Memory.self, from: data)
    XCTAssertEqual(resumed, memory)
  }
  func testNotificationNeverRedirectsToAnotherReceiver() {
    XCTAssertEqual(BackupNotifier.destination(notice: "convert", receiver: "pixel-a", current: "pixel-a"), .convert)
    XCTAssertNil(BackupNotifier.destination(notice: "full", receiver: "pixel-a", current: "pixel-b"))
    XCTAssertNil(BackupNotifier.destination(notice: "full", receiver: "pixel-a", current: nil))
    XCTAssertNil(BackupNotifier.destination(notice: "unknown", receiver: "pixel-a", current: "pixel-a"))
  }
  func testRoutineProgressAndUnconfirmedHistoryStayQuiet() {
    var memory = BackupNotifier.Memory()
    XCTAssertEqual(changes(.backingUp(remaining: 10, bytes: 100), &memory), [])
    XCTAssertEqual(changes(.caughtUp(lastSaved: nil, saving: 10), &memory), [])
    XCTAssertEqual(changes(.caughtUp(lastSaved: nil, saving: 0), &memory), [])
    let preparing = HistoricalImportStatus(run: 7, state: "scanning", checked: 10, pending: 10)
    let received = HistoricalImportStatus(run: 7, state: "scanned", checked: 10, pending: 0)
    XCTAssertEqual(changes(.empty, &memory, earlier: preparing), [.withdraw(.earlier)])
    XCTAssertEqual(changes(.empty, &memory, earlier: received), [])
    XCTAssertFalse(received.isSaved)
    let published = HistoricalImportStatus(run: 7, state: "scanned", checked: 10, pending: 0, published: 10)
    XCTAssertEqual(changes(.empty, &memory, earlier: published), [.post(.earlier)])
    memory.retry(.earlier)
    XCTAssertEqual(changes(.empty, &memory, earlier: published), [.post(.earlier)])
  }
}
