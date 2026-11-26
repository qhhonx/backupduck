import XCTest
@testable import BackupDuckCatalog

final class SubscriptionDistributionTests: XCTestCase {
  private let bundleID = "app.backupduck"

  func testTestPackagesIncludeProWithoutAcceptingPurchases() {
    for channel in [DuckProDistributionChannel.inHouse, .testFlight] {
      XCTAssertTrue(channel.allowsPro)
      XCTAssertTrue(channel.includesTestAccess)
      XCTAssertFalse(channel.allowsPurchases)
      XCTAssertFalse(channel.acceptsPurchase(in: .production))
      XCTAssertFalse(channel.acceptsPurchase(in: .sandbox))
    }
  }

  func testProductionEvidenceCannotEnableDirectDownloadCommerce() {
    let channel = DuckProDistributionChannel.resolve(storeTarget: false, bundleID: bundleID,
      evidence: .verified(environment: .production, bundleID: bundleID))
    XCTAssertEqual(channel, .directDownload)
    XCTAssertFalse(channel.allowsPro)
  }

  func testVerifiedSandboxAndDevelopmentKeepBackupUnrestricted() {
    for environment in [DuckProDistributionChannel.TransactionEnvironment.sandbox, .xcode, .unknown] {
      let channel = DuckProDistributionChannel.resolve(storeTarget: true, bundleID: bundleID,
        evidence: .verified(environment: environment, bundleID: bundleID))
      XCTAssertFalse(channel.allowsPro)
    }
  }

  func testUnverifiedAndMissingEvidenceCannotEnableCommerce() {
    for evidence in [DuckProDistributionChannel.Evidence.unverified, .unavailable] {
      let channel = DuckProDistributionChannel.resolve(storeTarget: true, bundleID: bundleID, evidence: evidence)
      XCTAssertEqual(channel, .unknown)
      XCTAssertFalse(channel.allowsPro)
    }
  }

  func testProductionEvidenceMustBelongToThisApplication() {
    let channel = DuckProDistributionChannel.resolve(storeTarget: true, bundleID: bundleID,
      evidence: .verified(environment: .production, bundleID: "app.other"))
    XCTAssertFalse(channel.allowsPro)
    XCTAssertFalse(DuckProDistributionChannel.resolve(storeTarget: true, bundleID: "",
      evidence: .verified(environment: .production, bundleID: "")).allowsPro)
  }

  func testVerifiedMatchingProductionEnablesPro() {
    let channel = DuckProDistributionChannel.resolve(storeTarget: true, bundleID: bundleID,
      evidence: .verified(environment: .production, bundleID: bundleID))
    XCTAssertEqual(channel, .appStore)
    XCTAssertTrue(channel.allowsPro)
    XCTAssertTrue(channel.acceptsPurchase(in: .production))
    XCTAssertFalse(channel.acceptsPurchase(in: .sandbox))
  }

  func testSubmissionArchiveAcceptsOnlyMatchingVerifiedSandboxPurchases() {
    let evidence = DuckProDistributionChannel.Evidence.verified(environment: .sandbox, bundleID: bundleID)
    let channel = DuckProDistributionChannel.resolve(storeTarget: true, bundleID: bundleID,
      evidence: evidence, submissionArchive: true)
    XCTAssertEqual(channel, .submissionSandbox)
    XCTAssertTrue(channel.allowsPro)
    XCTAssertTrue(channel.acceptsPurchase(in: .sandbox))
    XCTAssertFalse(channel.acceptsPurchase(in: .production))
    XCTAssertFalse(channel.acceptsPurchase(in: .xcode))

    let beta = DuckProDistributionChannel.resolve(storeTarget: true, bundleID: bundleID, evidence: evidence)
    XCTAssertFalse(beta.acceptsPurchase(in: .sandbox))
    for rejected in [
      DuckProDistributionChannel.resolve(storeTarget: false, bundleID: bundleID, evidence: evidence, submissionArchive: true),
      DuckProDistributionChannel.resolve(storeTarget: true, bundleID: "app.other", evidence: evidence, submissionArchive: true),
      DuckProDistributionChannel.resolve(storeTarget: true, bundleID: bundleID, evidence: .unverified, submissionArchive: true),
    ] {
      XCTAssertFalse(rejected.allowsPro)
      XCTAssertFalse(rejected.acceptsPurchase(in: .sandbox))
    }
  }
}
