import XCTest
import SwiftUI
import UIKit
import Photos
@testable import BackupDuckCatalog

/// Runs inside the separately identified catalog. No production application,
/// system permissions, real credentials or media library is used.
@MainActor final class ConnectPermissionTests: XCTestCase {
  func testDiagnosticsReadsLocalEventsBeforeForegroundEnvironmentArrives() async throws {
    try await withModel("diagnostics.root") { model, core in
      await model.open()
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let window = UIWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      window.rootViewController = UIHostingController(rootView: DiagnosticsView(model: model).environment(\.scenePhase, .inactive))
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(400))
      XCTAssertTrue(operations(core).contains("activity_log"), "Local diagnostics must not remain on Loading while scene propagation waits")
    }
  }

  func testDeniedPhotosStayOnStepAndReturningWithAccessAdvances() async throws {
    try await withModel("onboarding.photos-denied") { model, _ in
      await model.open()
      let defaults = UserDefaults(suiteName: "photos-step-" + UUID().uuidString)!
      let progress = IOSFirstRunProgress(defaults: defaults)
      progress.update { $0.step = "photos"; $0.receiver = model.pairing?.receiverID }
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let window = UIWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      window.rootViewController = UIHostingController(rootView: IOSOnboarding(model: model, progress: progress))
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(200))
      XCTAssertEqual(progress.record?.step, "photos")
      let previous = BackupEnvironment.photoAccess
      defer { BackupEnvironment.photoAccess = previous }
      BackupEnvironment.photoAccess = { .limited }
      model.refreshPhotoAccess()
      try await Task.sleep(for: .milliseconds(300))
      XCTAssertEqual(progress.record?.step, "choose")
      XCTAssertEqual(model.photoAccess, .limited)
    }
  }

  func testQueueNetworkWaitAloneDoesNotBypassProbeHysteresis() {
    var summary = SenderSummary()
    summary.waiting_reason = "network"; summary.waiting = 8
    let state = BackupHubStatus.derive(.init(paired: true, ready: true, paused: false,
      connection: .ready, receiverUnavailable: false, summary: summary,
      phoneSpaceShort: false, photoAccess: .full, photoLibraryInScope: true, jobs: []))
    XCTAssertEqual(state, .backingUp(remaining: 8, bytes: 0))
  }

  func testDockNeverIntersectsNativeIconAcrossActualBarWidthsAndReversal() {
    for width in [CGFloat(320), 375, 430, 768] {
      let bar = CGRect(x: 0, y: 700, width: width, height: 62)
      for frame in 0...120 {
        let fraction = CGFloat(frame <= 60 ? frame : 120 - frame) / 60
        let icon = CGRect(x: 16 + (width / 3 - 48) * (1 - fraction), y: 707, width: 48, height: 48)
        let capsule = LibraryDockGeometry.capsule(bar: bar, icon: icon, gap: DuckSpacing.small, inset: DuckSpacing.medium)
        XCTAssertGreaterThanOrEqual(capsule.minX - icon.maxX, DuckSpacing.small - 0.0001)
        XCTAssertLessThanOrEqual(capsule.maxX, bar.maxX - DuckSpacing.medium)
        XCTAssertFalse(icon.intersects(capsule))
      }
    }
  }

  func testProbeHysteresisKeepsLastStateAcrossPathUpdatesAndClearsOnSuccess() async {
    var now = Date(timeIntervalSince1970: 100)
    var answer = ReceiverConnection.ready
    var probes = 0
    let availability = ReceiverAvailability(monitorNetwork: false, now: { now },
      diagnose: { _ in probes += 1; return answer }, localNetworkDenied: { _ in false })
    let pairing = Pairing(version: 2, receiverID: "synthetic", endpoint: "https://127.0.0.1:1", certificate: "fixture", token: "fixture")
    availability.networkChanged(allowed: true)
    let initial = await availability.diagnose(pairing)
    XCTAssertEqual(initial, .ready)
    XCTAssertEqual(availability.visibleConnection, .ready)
    availability.networkChanged(allowed: false)
    XCTAssertEqual(availability.visibleConnection, .ready, "A path update alone is not a failed probe")
    availability.networkChanged(allowed: true)
    answer = .network
    let failed = await availability.diagnose(pairing)
    XCTAssertEqual(failed, .network, "Preparation stops immediately")
    XCTAssertEqual(availability.visibleConnection, .ready, "The hub retains its last state")
    now.addTimeInterval(9.99)
    XCTAssertEqual(availability.visibleConnection, .ready)
    now.addTimeInterval(0.01)
    XCTAssertEqual(availability.visibleConnection, .network)
    answer = .ready
    _ = await availability.diagnose(pairing, force: true)
    XCTAssertEqual(availability.visibleConnection, .ready)
    answer = .network
    _ = await availability.diagnose(pairing, force: true)
    XCTAssertEqual(availability.visibleConnection, .ready)
    _ = await availability.diagnose(pairing, force: true)
    XCTAssertEqual(availability.visibleConnection, .network, "Two actual failures are sufficient")
    XCTAssertEqual(probes, 5)
    answer = .ready
    _ = await availability.diagnose(pairing, force: true)
    XCTAssertEqual(availability.visibleConnection, .ready)
  }

  func testEarlierPhotosCompletionExpiresFromFirstSavedPresentationAcrossRestart() {
    let suite = "earlier-presentation-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let memory = EarlierPhotosCompletion(defaults: defaults)
    let now = Date(timeIntervalSince1970: 100)
    var history = HistoricalImportStatus(run: 9, state: "scanned", checked: 8, pending: 0, published: 7)
    XCTAssertNil(memory.show(receiver: "pixel", history: history, at: now))
    XCTAssertTrue(memory.visible(receiver: "pixel", history: history, at: now.addingTimeInterval(100000)))
    history.published = 8
    XCTAssertEqual(memory.show(receiver: "pixel", history: history, at: now), now)
    let restored = EarlierPhotosCompletion(defaults: defaults)
    XCTAssertEqual(restored.show(receiver: "pixel", history: history, at: now.addingTimeInterval(100)), now)
    XCTAssertTrue(restored.visible(receiver: "pixel", history: history, at: now.addingTimeInterval(86399)))
    XCTAssertFalse(restored.visible(receiver: "pixel", history: history, at: now.addingTimeInterval(86400)))
  }

  func testViewerOrdersFrozenCollectionsFromOlderToNewer() {
    let assets: [PHAsset] = [DatedCatalogAsset("new", 30), DatedCatalogAsset("old", 10), DatedCatalogAsset("middle", 20)]
    let session = MediaPreviewSession(asset: assets[2], library: PhotoLibraryModel(), reviewAssets: assets)
    XCTAssertEqual((0..<session.count).compactMap { session.asset(at: $0)?.localIdentifier }, ["old", "middle", "new"])
    XCTAssertEqual(session.adjacent(to: assets[2], direction: 1)?.localIdentifier, "new")
    XCTAssertEqual(session.adjacent(to: assets[2], direction: -1)?.localIdentifier, "old")
  }

  func testViewedAssetAloneRequestsNetworkAndKeepsPosterOnFailure() async throws {
    let original = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = original }
    let manager = PreviewRequestProbe()
    let poster = try XCTUnwrap(UIImage(systemName: "photo"))
    let preview = MediaPreviewModel(asset: PreviewRequestAsset(), poster: poster, manager: manager)
    preview.load(promptForCloud: false)
    XCTAssertEqual(manager.network, [false, false], "Adjacent pages keep local posters only")
    preview.activate()
    XCTAssertEqual(Array(manager.network.suffix(2)), [false, true], "Opening the page explicitly permits its display request")
    XCTAssertTrue(preview.image === poster)
    manager.results.last?(nil, [PHImageErrorKey: NSError(domain: PHPhotosErrorDomain, code: 3169), PHImageResultIsInCloudKey: true])
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertFalse(preview.loading)
    XCTAssertTrue(preview.failure)
    XCTAssertFalse(preview.cloudNeeded, "An allowed download failure is a Retry state")
    XCTAssertTrue(preview.image === poster, "Failure must preserve the low-resolution media")
    preview.cancel()
  }

  private let payload = #"{"version":2,"receiver_id":"catalog-pixel","endpoint":"https://127.0.0.1:1","certificate":"fixture","token":"fixture"}"#

  func testSelectionCatalogChromeSettlesAfterHostContainment() async throws {
    try await withModel("selection.review.selected") { model, _ in
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      for style in [UIUserInterfaceStyle.light, .dark] {
        let sample = SelectionReviewSample(mode: "selected", model: model, appearance: style)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style
        window.rootViewController = CalendarNavigationController(rootViewController: sample)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))
        let button = sample.calendar.selectedButton
        XCTAssertEqual(sample.calendar.selected.count, 12)
        XCTAssertTrue(button.isEnabled)
        XCTAssertNotNil(button.window)
        XCTAssertFalse(button.isHidden)
        XCTAssertEqual(button.alpha, 1)
        XCTAssertEqual(button.superview?.alpha, 1, "Catalog containment must not stop the reveal near zero opacity")
        XCTAssertFalse(button.superview?.isHidden ?? true)
        XCTAssertEqual(button.traitCollection.userInterfaceStyle, style)
      }
    }
  }

  func testAttentionGlyphContrastsWithResolvedNativeSurfaces() {
    func luminance(_ color: UIColor, traits: UITraitCollection) -> CGFloat {
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      XCTAssertTrue(color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
      XCTAssertEqual(alpha, 1)
      func linear(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    for style in [UIUserInterfaceStyle.light, .dark] {
      for contrast in [UIAccessibilityContrast.normal, .high] {
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast)])
        let glyph = luminance(DuckRole.attentionGlyphUIColor, traits: traits)
        for surface in [DuckRole.backgroundUIColor, DuckRole.groupedSurfaceUIColor, UIColor.systemBackground] {
          let background = luminance(surface, traits: traits)
          let ratio = (max(glyph, background) + 0.05) / (min(glyph, background) + 0.05)
          XCTAssertGreaterThanOrEqual(ratio, 3, "Appearance \(style), contrast \(contrast)")
        }
      }
    }
  }

  private func withModel(_ scenarioID: String = "onboarding.connect-camera-denied",
    body: (BackupModel, ScenarioCore) async throws -> Void) async throws {
    let core = ScenarioCore()
    let credentials = ScenarioCredentials()
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == scenarioID })
    let oldCore = BackupEnvironment.core
    let oldCredentials = BackupEnvironment.credentials
    let oldModel = BackupEnvironment.activeModel
    let oldRestore = BackupEnvironment.restoresSenderNetwork
    let oldPrepare = BackupEnvironment.prepareConnection
    BackupEnvironment.core = core
    BackupEnvironment.credentials = credentials
    let model = scenario.makeModel(core: core, credentials: credentials)
    core.setValue([:], for: "record_event")
    BackupEnvironment.activeModel = { model }
    defer {
      model.stop()
      BackupEnvironment.core = oldCore
      BackupEnvironment.credentials = oldCredentials
      BackupEnvironment.activeModel = oldModel
      BackupEnvironment.restoresSenderNetwork = oldRestore
      BackupEnvironment.prepareConnection = oldPrepare
      try? FileManager.default.removeItem(at: model.root)
    }
    try await body(model, core)
  }

  private func operations(_ core: ScenarioCore) -> [String] {
    core.commands.compactMap { command in
      (try? JSONSerialization.jsonObject(with: Data(command.utf8)) as? [String: Any])?["op"] as? String
    }
  }

  func testChineseQuestionFormatKeepsFullWidthPunctuation() throws {
    let bundle = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init(path:)))
    for key in ["onboarding_choose_earlier", "onboarding_choose_earlier_unknown"] {
      let value = bundle.localizedString(forKey: key, value: nil, table: nil)
      let question = String(format: value, "12,384")
      XCTAssertEqual(question.unicodeScalars.last?.value, 0xFF1F, key)
      XCTAssertFalse(question.contains("?"), key)
    }
  }

  func testEmptyLibraryKeepsLightSystemNavigation() async throws {
    try await withModel("hub.caught-up") { model, _ in
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let library = PhotoLibraryModel()
      library.installSyntheticAssets(EmptyCatalogAssets())
      let host = UIHostingController(rootView: IOSLibraryPage(library: library, model: model))
      let window = UIWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      window.overrideUserInterfaceStyle = .light
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(700))
      func navigationBars(_ view: UIView) -> [UINavigationBar] {
        (view as? UINavigationBar).map { [$0] } ?? view.subviews.flatMap(navigationBars)
      }
      let bars = navigationBars(host.view)
      XCTAssertFalse(bars.isEmpty)
      XCTAssertTrue(bars.allSatisfy { $0.traitCollection.userInterfaceStyle == .light })
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let capture = XCTAttachment(image: image)
      capture.name = "ios-empty-production-light"
      capture.lifetime = .keepAlways
      add(capture)
    }
  }

  func testSuccessfulSelectionRegistrationClosesReviewAndKeepsBriefFeedback() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let grid = CalendarGridController()
    grid.assets = (0..<2).map { CalendarGridAsset(id: "selected-\($0)", date: .now, aspect: 1) }
    grid.selected = Set(grid.assets.map(\.id))
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    window.rootViewController = CalendarNavigationController(rootViewController: grid)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(250))
    grid.selecting = true; grid.refreshSelection()
    grid.reviewSelection()
    try await Task.sleep(for: .milliseconds(350))
    XCTAssertNotNil(grid.presentedViewController)
    grid.setBackupFeedback(title: "Added to Backup", added: true)
    let dismissed = expectation(description: "Review sheet dismissed")
    grid.completeSelectedBackup { dismissed.fulfill() }
    await fulfillment(of: [dismissed], timeout: 3)
    XCTAssertFalse(grid.selecting)
    XCTAssertNil(grid.selectionReview)
    XCTAssertNil(grid.presentedViewController)
    XCTAssertTrue(grid.backupAdded)
  }

  func testMediaStatusBarFollowsVisibleTabAndScrim() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let grid = CalendarGridController()
    grid.assets = (0..<80).map { CalendarGridAsset(id: "status-\($0)", date: .now, aspect: 1) }
    let navigation = CalendarNavigationController(rootViewController: grid)
    let ordinary = UIViewController()
    let tabs = UITabBarController()
    tabs.viewControllers = [navigation, ordinary]
    // Exercise the same non-forwarding outer host as the SwiftUI app window.
    let host = UIViewController()
    host.addChild(tabs)
    host.view.addSubview(tabs.view)
    tabs.view.frame = scene.coordinateSpace.bounds
    tabs.didMove(toParent: host)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(250))
    let root = try XCTUnwrap(window.rootViewController)
    XCTAssertTrue(root.childForStatusBarStyle === navigation)
    XCTAssertEqual(navigation.preferredStatusBarStyle, .lightContent)
    grid.selected = [grid.assets[0].id]
    grid.reviewSelection()
    try await Task.sleep(for: .milliseconds(350))
    let sheet = try XCTUnwrap(grid.presentedViewController)
    XCTAssertEqual(sheet.preferredStatusBarStyle, .lightContent)
    XCTAssertTrue(root.childForStatusBarStyle === navigation)
    grid.dismiss(animated: false)
    grid.assets = []
    grid.updateMediaHeader()
    XCTAssertEqual(navigation.preferredStatusBarStyle, .default)
    tabs.selectedIndex = 1
    XCTAssertTrue(root.childForStatusBarStyle === host)
  }

  func testFirstRunNativeBackPreservesRegisteredIntent() async throws {
    try await withModel("onboarding.connected") { model, core in
      await model.open()
      let progress = IOSFirstRunProgress(defaults: UserDefaults(suiteName: "catalog-back-" + UUID().uuidString)!)
      progress.update {
        $0.step = "photos"; $0.receiver = model.pairing?.receiverID
        $0.autoBackup = true; $0.earlierPhotos = true; $0.scopeRegistered = true
      }
      let receiver = model.pairing?.receiverID
      let host = UIHostingController(rootView: IOSOnboarding(model: model, progress: progress))
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let window = UIWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.layoutIfNeeded()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(400))
      func navigation(_ controller: UIViewController) -> UINavigationController? {
        if let found = controller as? UINavigationController { return found }
        return controller.children.lazy.compactMap { navigation($0) }.first
      }
      let nav = try XCTUnwrap(navigation(host))
      XCTAssertFalse(nav.navigationBar.isHidden)
      XCTAssertGreaterThan(nav.viewControllers.count, 1)
      XCTAssertNotNil(nav.popViewController(animated: false))
      try await Task.sleep(for: .milliseconds(200))
      XCTAssertEqual(progress.record?.step, "connected")
      XCTAssertEqual(progress.record?.receiver, receiver)
      XCTAssertEqual(progress.record?.scopeRegistered, true)
      XCTAssertEqual(progress.record?.earlierPhotos, true)
      XCTAssertEqual(model.pairing?.receiverID, receiver)
    }
  }

  func testDiagnosticsHidesUnknownEventsButPreservesExport() async throws {
    let entries = [
      ActivityEntry(id: 2, timestamp: 2, code: "future_event_v3", job_id: nil, bytes: nil, context: nil),
      ActivityEntry(id: 1, timestamp: 1, code: "sender_ready", job_id: nil, bytes: nil, context: nil),
    ]
    let journal = ActivityLogModel { _ in .init(entries: entries, oldest_id: 1, newest_id: 2, reset: true) }
    await journal.refresh { true }
    XCTAssertEqual(journal.entries.map(\.id), [2, 1])
    XCTAssertEqual(journal.recentEntries.map(\.id), [1])
    let bytes = Data(#"[{"code":"future_event_v3","future":{"value":42}}]"#.utf8)
    let export = ActivityLogExportModel(snapshot: { bytes })
    await export.prepare()
    let url = try XCTUnwrap(export.url)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    try FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }

  func testCameraDeniedLaunchAndForegroundNeverStartNetwork() async throws {
    try await withModel { model, core in
      var preparations = 0
      BackupEnvironment.prepareConnection = { _ in preparations += 1 }
      await model.open()
      await model.becameActive()
      await model.checkConnection()
      await model.refreshReceiverReadings()
      await model.recoverBackgroundReceiverRoute()
      BackgroundTransfer.shared.connect()
      BackgroundTransfer.shared.enteredForeground()
      BackgroundTransfer.shared.enteredBackground()
      await BackgroundTransfer.shared.cancelAll()
      await BackgroundTransfer.shared.record("catalog_scan_snapshot")
      await BackgroundTransfer.shared.recordSnapshot("catalog_scan_snapshot")
      _ = TransferDiagnostics.shared.snapshot()
      XCTAssertTrue(model.ready)
      XCTAssertNil(model.pairing)
      XCTAssertFalse(model.networkingStarted)
      XCTAssertFalse(BackgroundTransfer.shared.sessionStarted)
      XCTAssertFalse(TransferDiagnostics.shared.monitoring)
      XCTAssertEqual(preparations, 0)
      let forbidden: Set<String> = ["check_pairing", "exchange_device", "receiver_readings", "watch_processing", "refresh_processing", "prepare_native"]
      XCTAssertTrue(forbidden.isDisjoint(with: operations(core)))
    }
  }

  func testRestoredTrustBehindScanDoesNotStartWorkers() async throws {
    try await withModel("onboarding.connected") { model, core in
      BackupEnvironment.restoresSenderNetwork = { false }
      await model.open()
      await model.becameActive()
      await model.checkConnection()
      await model.refreshReceiverReadings()
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertNotNil(model.pairing)
      XCTAssertFalse(model.networkingStarted)
      XCTAssertFalse(operations(core).contains("check_pairing"))
      XCTAssertFalse(operations(core).contains("exchange_device"))
      XCTAssertFalse(operations(core).contains("watch_processing"))
    }
  }

  func testFirstRunRestorationOnlyPermitsNetworkAfterConnect() throws {
    let suite = "catalog.permission-tests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertFalse(IOSFirstRunProgress.allowsRestoredNetwork(defaults: defaults))
    let progress = IOSFirstRunProgress(defaults: defaults)
    for step in ["welcome", "install", "connect"] {
      progress.update { $0.step = step }
      XCTAssertFalse(IOSFirstRunProgress.allowsRestoredNetwork(defaults: defaults))
    }
    for step in ["connected", "photos", "choose", "first"] {
      progress.update { $0.step = step }
      XCTAssertTrue(IOSFirstRunProgress.allowsRestoredNetwork(defaults: defaults))
    }
    progress.leave()
    XCTAssertTrue(IOSFirstRunProgress.allowsRestoredNetwork(defaults: defaults))
  }

  func testInvalidCodeDoesNotBeginPermissionPreflight() async throws {
    try await withModel { model, core in
      var requests = 0
      BackupEnvironment.prepareConnection = { _ in requests += 1 }
      let paired = await model.pair("not-a-code")
      XCTAssertFalse(paired)
      XCTAssertEqual(requests, 0)
      XCTAssertFalse(operations(core).contains("check_pairing"))
    }
  }

  func testDeniedAccessStopsBeforeTLSAndKeepsTrustForRetry() async throws {
    try await withModel("onboarding.connected") { model, core in
      BackupEnvironment.restoresSenderNetwork = { false }
      await model.open()
      let previous = model.pairing?.receiverID
      let retryPayload = String(decoding: try JSONEncoder().encode(XCTUnwrap(model.pairing)), as: UTF8.self)
      for failure in [ConnectAccessFailure.wireless, .localNetwork, .unavailable] {
        BackupEnvironment.prepareConnection = { _ in throw failure }
        let paired = await model.pair(retryPayload)
        XCTAssertFalse(paired)
        XCTAssertTrue(model.pairingNeedsSettings)
        XCTAssertEqual(model.pairingError, failure.localizedDescription)
        XCTAssertEqual(model.pairing?.receiverID, previous)
        XCTAssertFalse(model.networkingStarted)
        XCTAssertFalse(operations(core).contains("check_pairing"))
      }
      BackupEnvironment.prepareConnection = { _ in }
      let retried = await model.pair(retryPayload)
      XCTAssertTrue(retried)
      XCTAssertTrue(model.networkingStarted)
      XCTAssertFalse(model.pairingNeedsSettings)
      XCTAssertTrue(operations(core).contains("check_pairing"))
    }
  }

  func testTLSWaitsForPreflightAndCancellationDoesNotSaveTrust() async throws {
    try await withModel { model, core in
      var reply: CheckedContinuation<Void, Never>?
      BackupEnvironment.prepareConnection = { _ in
        await withCheckedContinuation { reply = $0 }
      }
      let task = Task { await model.pair(payload) }
      for _ in 0..<100 where reply == nil { await Task.yield() }
      XCTAssertNotNil(reply)
      XCTAssertFalse(operations(core).contains("check_pairing"))
      task.cancel()
      reply?.resume()
      let result = await task.value
      XCTAssertFalse(result)
      XCTAssertNil(model.pairing)
      XCTAssertFalse(operations(core).contains("check_pairing"))
    }
  }

  func testCameraRecoveryAndConnectionRetryHaveSeparateIntent() {
    let state = IOSPixelScannerState()
    state.cameraFailure = .permission
    let scanner = state.scannerID
    state.cameraAuthorizationChanged(false)
    XCTAssertEqual(state.scannerID, scanner)
    XCTAssertTrue(state.needsSettings)
    state.cameraAuthorizationChanged(true)
    XCTAssertNotEqual(state.scannerID, scanner)
    XCTAssertFalse(state.needsRecovery)
    XCTAssertNil(state.payload)
    state.payload = payload
    state.scanError = "denied"
    state.connectionNeedsSettings = true
    state.retry()
    XCTAssertEqual(state.payload, payload)
    XCTAssertEqual(state.connectionAttempt, 1)
    state.scanAgain()
    XCTAssertNil(state.payload)
  }

  func testDismissalDuringTLSDoesNotPersistSuccessfulLateReply() async throws {
    try await withModel { model, core in
      let delayed = DelayedPairingCore(base: core)
      BackupEnvironment.core = delayed
      BackupEnvironment.prepareConnection = { _ in }
      let task = Task { await model.pair(payload) }
      for _ in 0..<100 {
        if await delayed.waiting { break }
        await Task.yield()
      }
      let waiting = await delayed.waiting
      XCTAssertTrue(waiting)
      task.cancel()
      await delayed.release()
      let result = await task.value
      XCTAssertFalse(result)
      XCTAssertNil(model.pairing)
      XCTAssertFalse(model.networkingStarted)
    }
  }
}

private actor DelayedPairingCore: CoreTransport {
  let base: ScenarioCore
  private(set) var waiting = false
  private var reply: CheckedContinuation<Void, Never>?
  init(base: ScenarioCore) { self.base = base }
  func call(_ command: String) async throws -> Data {
    let operation = (try JSONSerialization.jsonObject(with: Data(command.utf8)) as? [String: Any])?["op"] as? String
    if operation == "check_pairing" {
      await withCheckedContinuation { reply = $0; waiting = true }
    }
    return try await base.call(command)
  }
  func release() { reply?.resume(); reply = nil }
}

/// An empty in-memory collection never queries or changes the simulator library.
private final class EmptyCatalogAssets: PHFetchResult<PHAsset>, @unchecked Sendable {
  override var count: Int { 0 }
}

private final class PreviewRequestAsset: PHAsset, @unchecked Sendable {
  override var localIdentifier: String { "network-probe" }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 800 }
  override var pixelHeight: Int { 600 }
}
private final class PreviewRequestProbe: PHImageManager {
  var network: [Bool] = []
  var results: [(UIImage?, [AnyHashable: Any]?) -> Void] = []
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    network.append(options?.isNetworkAccessAllowed ?? false); results.append(resultHandler)
    return PHImageRequestID(results.count)
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) {}
}

private final class DatedCatalogAsset: PHAsset, @unchecked Sendable {
  let identifier: String
  let date: Date
  init(_ identifier: String, _ timestamp: TimeInterval) { self.identifier = identifier; date = Date(timeIntervalSince1970: timestamp); super.init() }
  override var localIdentifier: String { identifier }
  override var creationDate: Date? { date }
  override var mediaType: PHAssetMediaType { .image }
  override var burstIdentifier: String? { nil }
}
