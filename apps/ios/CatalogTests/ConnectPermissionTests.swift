import XCTest
import Combine
import SwiftUI
import AVFoundation
import UIKit
import Photos
@testable import BackupDuckCatalog

private actor ChangingReceiverFixture {
  let fixture: CatalogLibraryFixture
  private var queries = 0
  init(_ fixture: CatalogLibraryFixture) { self.fixture = fixture }
  func fetch(filter: LibraryFilter, view: LibraryBackupView) -> PHFetchResult<PHAsset> {
    let result = fixture.fetch(filter: filter, view: view)
    guard view == .notBackedUp else { return result }
    queries += 1
    guard queries > 1 else { return result }
    return CatalogAssetCollection((1..<result.count).map { result.object(at: $0) })
  }
}

/// Runs inside the separately identified catalog. No production application,
/// system permissions, real credentials or media library is used.
@MainActor final class ConnectPermissionTests: XCTestCase {
  func testReadingPairingAtStartupDoesNotPublishAnError() async throws {
    for (scenario, hasPairing) in [("onboarding.welcome", false), ("hub.caught-up", true)] {
      try await withModel(scenario) { model, _ in
        var messages: [String] = []
        let observation = model.$message.compactMap { $0 }.sink { messages.append($0) }
        await model.open()
        withExtendedLifetime(observation) {
          XCTAssertTrue(model.ready, scenario)
          XCTAssertEqual(model.pairing != nil, hasPairing, scenario)
          XCTAssertTrue(messages.isEmpty, scenario)
        }
      }
    }
  }

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
    XCTAssertEqual(state, .backingUp(remaining: 8, bytes: nil))
  }

  func testDockIsCentredBesideTheSettledNativeIcon() {
    for width in [CGFloat(320), 375, 430, 768] {
      let icon = CGRect(x: 28, y: 707, width: 48, height: 48)
      let capsule = LibraryDockGeometry.capsule(width: width, icon: icon)
      XCTAssertEqual(capsule.minX - icon.maxX, 12, accuracy: 0.0001)
      XCTAssertEqual(width - capsule.maxX, icon.maxX + 12, accuracy: 0.0001)
      XCTAssertEqual(capsule.midY, icon.midY, accuracy: 0.0001)
      XCTAssertFalse(icon.intersects(capsule))
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
        let navigation = CalendarNavigationController(rootViewController: sample)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))
        let item = try XCTUnwrap(navigation.topViewController?.toolbarItems?.first {
          $0.accessibilityIdentifier == "calendar.review_selected"
        })
        XCTAssertEqual(sample.calendar.selected.count, 12)
        XCTAssertTrue(item.isEnabled)
        XCTAssertTrue(sample.toolbarItems?.contains { $0 === item } == true,
          "The navigation stack's container must own the calendar's persistent toolbar items")
        XCTAssertTrue(sample.calendar.toolbarItems?.contains { $0 === item } == true)
        XCTAssertFalse(navigation.isToolbarHidden)
        // Floating toolbar groups on current systems are hosted outside the
        // legacy UIToolbar view. The navigation page must remain attached.
        XCTAssertNotNil(navigation.view.window)
        XCTAssertEqual(navigation.toolbar.traitCollection.userInterfaceStyle, style)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let capture = XCTAttachment(image: image)
        capture.name = "native-selection-toolbar-\(style == .light ? "light" : "dark")"
        capture.lifetime = .keepAlways
        add(capture)
        sample.calendar.toggleSelection()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(navigation.isToolbarHidden)
        sample.calendar.toggleSelection()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(navigation.isToolbarHidden)
        XCTAssertFalse(item.isEnabled, "Re-entering selection starts with no selected photos")
      }
    }
  }

  func testProductionCalendarHostOwnsSelectionToolbarAndRestoresNavigation() async throws {
    try await withModel("selection.review.selected") { model, _ in
      let previous = BackupEnvironment.usesPhotoLibrary
      BackupEnvironment.usesPhotoLibrary = false
      defer { BackupEnvironment.usesPhotoLibrary = previous }
      let library = PhotoLibraryModel()
      library.installSyntheticAssets(CatalogLibraryFixture(count: 48).fetch(filter: .all, view: .all))
      let previousDensity = UserDefaults.standard.object(forKey: CalendarGridController.densityKey)
      UserDefaults.standard.set(5, forKey: CalendarGridController.densityKey)
      defer { UserDefaults.standard.set(previousDensity, forKey: CalendarGridController.densityKey) }
      let action = SelectionBackupAction()
      let host = UIHostingController(rootView: IOSCalendarLibrary(library: library, model: model, backupAction: action))
      let tabs = UITabBarController()
      tabs.viewControllers = [host, UIViewController()]
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let window = UIWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      window.rootViewController = tabs
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(500))
      func calendar(in controller: UIViewController) -> CalendarGridController? {
        if let grid = controller as? CalendarGridController { return grid }
        return controller.children.lazy.compactMap { calendar(in: $0) }.first
      }
      let grid = try XCTUnwrap(calendar(in: host))
      let navigation = try XCTUnwrap(grid.navigationController)
      XCTAssertEqual(grid.layout.geometry.columns, 5)
      grid.selecting = true
      library.selection = Set(grid.assets.prefix(2).map(\.id))
      grid.selected = library.selection
      grid.refreshSelection()
      try await Task.sleep(for: .milliseconds(400))
      let item = try XCTUnwrap(navigation.topViewController?.toolbarItems?.first { $0.accessibilityIdentifier == "calendar.review_selected" })
      XCTAssertTrue(item.isEnabled)
      XCTAssertTrue(navigation.topViewController === grid)
      XCTAssertFalse(navigation.isToolbarHidden)
      XCTAssertTrue(tabs.isTabBarHidden)
      let selected = grid.selected
      grid.reviewSelection()
      let review = try XCTUnwrap(grid.selectionReview)
      for _ in 0..<100 where review.navigationController?.isBeingPresented != false {
        try await Task.sleep(for: .milliseconds(20))
      }
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(review.columns, 3)
      XCTAssertNotNil(review.navigationController)
      review.onPreview(review)
      for _ in 0..<100 where review.presentedViewController == nil {
        try await Task.sleep(for: .milliseconds(20))
      }
      let previewNavigation = try XCTUnwrap(review.presentedViewController as? UINavigationController)
      let preview = try XCTUnwrap(previewNavigation.topViewController as? NativeMediaViewer)
      for _ in 0..<100 where previewNavigation.isBeingPresented {
        try await Task.sleep(for: .milliseconds(20))
      }
      let previewAction = try XCTUnwrap(preview.toolbarItems?.first {
        $0.accessibilityIdentifier == "calendar.selected_preview_backup"
      })
      XCTAssertFalse(previewNavigation.isToolbarHidden)
      XCTAssertTrue(previewAction.isEnabled)
      XCTAssertEqual(previewAction.title, review.backupItem.title)
      XCTAssertEqual(preview.toolbarItems?.filter { $0.action != nil }.count, 1,
        "Detail retains the shared backup action, without a global deselect action")
      preview.selectionButton.sendActions(for: .touchUpInside)
      XCTAssertEqual(review.selected.count, selected.count - 1)
      XCTAssertEqual(previewAction.title, review.backupItem.title)
      preview.selectionButton.sendActions(for: .touchUpInside)
      XCTAssertEqual(review.selected, selected)
      let registration = review.onBackup
      var registrations: [Set<String>] = []
      review.onBackup = { registrations.append(review.selected) }
      UIApplication.shared.sendAction(try XCTUnwrap(previewAction.action), to: previewAction.target, from: previewAction, for: nil)
      XCTAssertEqual(registrations, [selected], "Detail backs up the full reviewed set through the existing action")
      review.setBackupFeedback(title: "Preparing", enabled: false, added: false)
      XCTAssertFalse(previewAction.isEnabled)
      UIApplication.shared.sendAction(try XCTUnwrap(previewAction.action), to: previewAction.target, from: previewAction, for: nil)
      XCTAssertEqual(registrations.count, 1, "Registration is guarded while the shared action is busy")
      review.onBackup = registration
      review.setBackupFeedback(title: "", enabled: true, added: false)
      func waitForDetailDialog() async throws -> UIAlertController {
        for _ in 0..<100 where preview.presentedViewController == nil {
          try await Task.sleep(for: .milliseconds(20))
        }
        let dialog = try XCTUnwrap(preview.presentedViewController as? UIAlertController)
        for _ in 0..<100 where dialog.isBeingPresented {
          try await Task.sleep(for: .milliseconds(20))
        }
        return dialog
      }
      func dismissDetailDialog(_ dialog: UIAlertController) async throws {
        dialog.dismiss(animated: false)
        for _ in 0..<100 where preview.presentedViewController != nil {
          try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(preview.presentedViewController)
      }
      // Exercise the real toolbar callback and action. Synthetic assets cannot
      // resolve PhotoKit originals, so the request must expose its failure in
      // detail without touching real media or registering preparation work.
      model.pairing = try JSONDecoder().decode(Pairing.self, from: Data(payload.utf8))
      UIApplication.shared.sendAction(try XCTUnwrap(previewAction.action), to: previewAction.target, from: previewAction, for: nil)
      let failure = try await waitForDetailDialog()
      XCTAssertEqual(failure.preferredStyle, .alert)
      XCTAssertEqual(failure.title, NSLocalizedString("selection_backup_failed_title", comment: ""))
      XCTAssertEqual(failure.message, NSLocalizedString("error_source_unavailable", comment: ""))
      XCTAssertEqual(action.error, failure.message)
      XCTAssertFalse(action.busy)
      XCTAssertTrue(previewAction.isEnabled)
      XCTAssertEqual(library.selection, selected)
      library.selection = selected
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertTrue(preview.presentedViewController === failure)
      XCTAssertNil(failure.presentedViewController, "A host refresh must not stack another alert")
      action.error = nil
      try await dismissDetailDialog(failure)

      // Repeat detection needs PhotoKit source revisions. Supply only its UI
      // observation here; this does not claim to test request-side detection.
      action.confirmingRepeat = true
      let confirmation = try await waitForDetailDialog()
      XCTAssertEqual(confirmation.preferredStyle, .actionSheet)
      XCTAssertEqual(confirmation.title, NSLocalizedString("selection_backup_repeat_title", comment: ""))
      XCTAssertTrue(confirmation.actions.contains { $0.style == .cancel })
      XCTAssertTrue(confirmation.popoverPresentationController?.barButtonItem === previewAction,
        "A selected-detail confirmation uses the visible clone as its popover anchor")
      library.selection = selected
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertTrue(preview.presentedViewController === confirmation)
      XCTAssertNil(confirmation.presentedViewController, "An existing confirmation retains its presentation ownership")
      // This is the same cancellation method used by the native Cancel action.
      action.cancel()
      try await dismissDetailDialog(confirmation)
      XCTAssertFalse(action.confirmingRepeat)
      XCTAssertEqual(library.selection, selected)
      XCTAssertEqual(review.selected, selected)
      XCTAssertTrue(review.presentedViewController === previewNavigation)
      XCTAssertTrue(previewAction.isEnabled)
      let detailImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let detailCapture = XCTAttachment(image: detailImage)
      detailCapture.name = "selected-detail-native-backup-toolbar"
      detailCapture.lifetime = .keepAlways
      add(detailCapture)
      preview.dismissViewer()
      for _ in 0..<100 where review.presentedViewController != nil {
        try await Task.sleep(for: .milliseconds(20))
      }
      XCTAssertNil(review.presentedViewController)
      review.done()
      for _ in 0..<100 where navigation.presentedViewController != nil {
        try await Task.sleep(for: .milliseconds(20))
      }
      XCTAssertNil(navigation.presentedViewController)
      XCTAssertEqual(grid.selected, selected)
      XCTAssertEqual(grid.columns, 5)
      XCTAssertEqual(grid.layout.geometry.columns, 5)
      XCTAssertFalse(navigation.isToolbarHidden)
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let capture = XCTAttachment(image: image)
      capture.name = "production-calendar-native-selection-toolbar"
      capture.lifetime = .keepAlways
      add(capture)
      grid.toggleSelection()
      try await Task.sleep(for: .milliseconds(400))
      XCTAssertTrue(navigation.isToolbarHidden)
      XCTAssertFalse(tabs.isTabBarHidden)
      XCTAssertEqual(grid.columns, 5)
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

  func testLimitedDiscoveryUsesOnlyFetchedIdentifiers() {
    let observed: Set<String> = ["readable-photo", "outside-selection", "missing-original"]
    var fetches = 0
    let fetch: (Set<String>) -> Set<String> = { ids in
      fetches += 1; XCTAssertEqual(ids, observed)
      return ["readable-photo", "unrelated"]
    }
    XCTAssertEqual(PhotoLibraryChanges.readableIdentifiers(observed, limited: true, fetch: fetch), ["readable-photo"])
    XCTAssertEqual(fetches, 1)
    XCTAssertEqual(PhotoLibraryChanges.readableIdentifiers(observed, limited: false, fetch: fetch), observed)
    XCTAssertEqual(fetches, 1, "Full access keeps genuine missing originals actionable")
  }

  func testAppearanceUpdatesAllWindowsAndUIKitPresentationsImmediately() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let windows = (0..<2).map { _ in UIWindow(windowScene: scene) }
    for window in windows {
      let root = UIViewController(); let native = UINavigationController(rootViewController: root)
      window.rootViewController = native; window.makeKeyAndVisible()
    }
    defer { windows.forEach { $0.isHidden = true } }
    for (choice, expected) in [("dark", UIUserInterfaceStyle.dark), ("light", .light), ("system", .unspecified)] {
      IOSAppearanceBridge.apply(choice, windows: windows)
      try await Task.sleep(for: .milliseconds(30))
      for window in windows {
        XCTAssertEqual(window.overrideUserInterfaceStyle, expected)
        if expected != .unspecified {
          XCTAssertEqual(window.rootViewController?.traitCollection.userInterfaceStyle, expected)
          XCTAssertEqual(window.rootViewController?.children.first?.traitCollection.userInterfaceStyle, expected)
        }
      }
    }
  }

  func testNeedsYouCountAgreesAcrossHubAndHistory() async throws {
    var legacy = SenderSummary()
    legacy.failed = 1; legacy.publication_failed = 1; legacy.preparation_failed = 1
    XCTAssertEqual(legacy.count(for: "attention"), 3, "Legacy summaries still include preparation failures")
    try await withModel("hub.conversion") { model, core in
      let sources = ["attention-transfer", "attention-publication", "attention-original"]
      var items: [[String: Any]] = []
      for (index, source) in sources.enumerated() {
        if index == 2 {
          items.append(["id": "preparation:original", "cursor": -1, "sort_value": 100,
            "preparation": ["cursor": -1, "request_id": "original", "source": source, "revision": "1", "error_code": "source_unavailable"]])
        } else {
          items.append(["id": "job-\(index)", "cursor": index + 1, "sort_value": 100,
            "job": ["id": index + 1, "state": index == 0 ? "failed" : "received", "confirmed_bytes": 0,
              "processing": index == 0 ? "not_requested" : "failed",
              "asset": ["source_id": source, "revision": "1", "kind": "photo", "resources": [["filename": "Example.jpg", "size": 10]]]]])
        }
      }
      let summary: [String: Any] = ["total": 3, "attention": 3, "active": 0, "saved": 0,
        "failed": 1, "publication_failed": 1, "preparation_failed": 1,
        "received": 1, "published": 0, "waiting": 0, "queued": 0, "running": 0, "paused": 0, "confirmed_bytes": 0]
      core.setValue(summary, for: "backup_summary")
      core.setValue(["items": items, "summary": summary], for: "backup_tasks")
      await model.open()
      let history = BackupHistoryModel(); await history.reload(receiver: "catalog-pixel", state: "attention")
      // The hub summary arrives from the model's own asynchronous refresh.
      for _ in 0..<100 where model.summary.count(for: "attention") != 3 { try await Task.sleep(for: .milliseconds(20)) }
      XCTAssertEqual(model.summary.count(for: "attention"), 3)
      XCTAssertEqual(history.total, 3); XCTAssertEqual(history.attention.count, 3)
      XCTAssertTrue(history.attention.allSatisfy { $0.mark == .needsYou })
    }
  }

  func testLargeMembershipCommitsFiltersAndRowsTogether() async throws {
    let original = BackupEnvironment.usesPhotoLibrary; BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = original }
    let fixture = CatalogLibraryFixture(count: 55_000)
    let library = PhotoLibraryModel()
    library.installSyntheticAssets(fixture.fetch(filter: .all, view: .all))
    library.syntheticFetch = { filter, view in
      try? await Task.sleep(for: .milliseconds(50))
      return fixture.fetch(filter: filter, view: view)
    }
    let change = Task { await library.changeBackupView(.notBackedUp) }
    await Task.yield()
    XCTAssertEqual(library.backupView, .all); XCTAssertEqual(library.total, 55_000)
    await change.value
    let remaining = fixture.fetch(filter: .all, view: .notBackedUp)
    XCTAssertEqual(library.backupView, .notBackedUp); XCTAssertEqual(library.total, remaining.count)
    XCTAssertEqual(library.membership?.rows.count, remaining.count)
    XCTAssertEqual(Set(library.membership?.rows.map(\.id) ?? []), Set((0..<remaining.count).map { remaining.object(at: $0).localIdentifier }))
    await library.changeFilter(.video)
    XCTAssertEqual(library.filter, .video)
    XCTAssertEqual(library.total, fixture.fetch(filter: .video, view: .notBackedUp).count)
  }

  func testReturningToNotBackedUpUsesCurrentReceiverMembership() async {
    let original = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = original }
    let fixture = CatalogLibraryFixture(count: 700)
    let receiver = ChangingReceiverFixture(fixture)
    let library = PhotoLibraryModel()
    library.installSyntheticAssets(fixture.fetch(filter: .all, view: .all))
    library.syntheticFetch = { filter, view in await receiver.fetch(filter: filter, view: view) }

    await library.changeBackupView(.notBackedUp)
    let first = Set(library.membership?.rows.map(\.id) ?? [])
    await library.changeBackupView(.all)
    await library.changeBackupView(.notBackedUp)
    let second = Set(library.membership?.rows.map(\.id) ?? [])
    XCTAssertFalse(first.isEmpty)
    XCTAssertFalse(second.isEmpty)
    XCTAssertNotEqual(first, second, "Returning must use the receiver's latest answer")
    XCTAssertEqual(first.count, second.count + 1)
  }

  func testMembershipCacheRejectsStaleAndReceiptDependentSnapshots() throws {
    let fixture = CatalogLibraryFixture(count: 500)
    let all = fixture.fetch(filter: .all, view: .all)
    let videos = fixture.fetch(filter: .video, view: .all)
    var cache = LibraryMembershipCache()
    let epoch = cache.epoch
    cache.put((all, LibraryMembership(all)), filter: .all, view: .all, epoch: epoch)
    cache.put((videos, LibraryMembership(videos)), filter: .video, view: .all, epoch: epoch)
    XCTAssertTrue(try XCTUnwrap(cache.get(.all, view: .all)).0 === all)
    XCTAssertTrue(try XCTUnwrap(cache.get(.video, view: .all)).0 === videos)
    XCTAssertNil(cache.get(.all, view: .notBackedUp))

    cache.put((videos, LibraryMembership(videos)), filter: .photo, view: .notBackedUp, epoch: epoch)
    XCTAssertNil(cache.get(.photo, view: .all), "Receipt-dependent answers cannot enter the reusable cache")
    cache.invalidate()
    XCTAssertNil(cache.get(.all, view: .all))
    cache.put((all, LibraryMembership(all)), filter: .all, view: .all, epoch: epoch)
    XCTAssertNil(cache.get(.all, view: .all), "An old worker cannot repopulate after a library or permission change")
    cache.put((videos, LibraryMembership(videos)), filter: .video, view: .all, epoch: cache.epoch)
    XCTAssertEqual(cache.get(.video, view: .all)?.1.rows.count, videos.count)
  }

  func testNativeFilterReplacementRestoresRetainedAnchor() throws {
    let rows = LibraryMembership(CatalogLibraryFixture(count: 2_000).fetch(filter: .all, view: .all)).rows
    let grid = CalendarGridController()
    grid.loadViewIfNeeded(); grid.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    grid.view.layoutIfNeeded(); grid.replaceAssets(rows)
    grid.locateAsset(1_000)
    let anchor = try XCTUnwrap(grid.browsingAnchor())
    grid.replaceAssets(Array(rows.suffix(2)), newView: true)
    XCTAssertEqual(grid.leadingSlots, 0)
    grid.replaceAssets(rows, newView: true, anchor: anchor)
    let index = try XCTUnwrap(grid.assets.firstIndex { $0.id == anchor.id })
    XCTAssertEqual(grid.layout.frame(index).minY - grid.grid.contentOffset.y, anchor.screenY, accuracy: 1)
    XCTAssertEqual(grid.leadingSlots, anchor.leadingSlots)
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

  #if targetEnvironment(simulator)
  func testPairingPreviewIsVisibleInsideActualScanPages() async throws {
    try await withModel { model, _ in
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let progress = IOSFirstRunProgress(defaults: UserDefaults(suiteName: "scan-preview-" + UUID().uuidString)!)
      progress.update { $0.step = "connect"; $0.navigationPath = ["install", "connect"] }
      let pages = [AnyView(IOSOnboarding(model: model, progress: progress)), AnyView(IOSConnectSheet(model: model))]
      for (index, page) in pages.enumerated() {
        var previewLayer: AVCaptureVideoPreviewLayer?
        ScannerController.simulatedPreview = { previewLayer = $0 }
        defer { ScannerController.simulatedPreview = nil }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = index == 0 ? .light : .dark
        window.rootViewController = UIHostingController(rootView: page)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(700))
        let layer = try XCTUnwrap(previewLayer)
        let rect = layer.convert(layer.bounds, to: window.layer)
        XCTAssertTrue((layer.delegate as? UIView)?.layer === layer)
        print("Pairing preview case \(index), screen \(window.bounds), visible layer \(rect)")
        XCTAssertGreaterThan(rect.width, window.bounds.width * 0.75)
        XCTAssertEqual(rect.height, 300, accuracy: 1)
        XCTAssertTrue(window.bounds.contains(rect))
        guard rect.width > 0 && rect.height > 0 else { continue }
        let marker = CALayer()
        marker.frame = layer.bounds
        marker.backgroundColor = UIColor.magenta.cgColor
        layer.addSublayer(marker)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(150))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let shot = XCTAttachment(image: image)
        shot.name = "Pairing preview \(index)"
        shot.lifetime = .keepAlways
        self.add(shot)
        for x in [rect.minX + 16, rect.midX, rect.maxX - 16] {
          let sample = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: x.rounded(), y: rect.midY.rounded(), width: 1, height: 1)))
          var rgba = [UInt8](repeating: 0, count: 4)
          let context = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
          XCTAssertGreaterThan(rgba[0], 220)
          XCTAssertLessThan(rgba[1], 35)
          XCTAssertGreaterThan(rgba[2], 220)
        }
      }
    }
  }

  func testInterruptedCameraOffersRecoveryAndRetryUsesANewPreview() async throws {
    try await withModel { model, _ in
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let progress = IOSFirstRunProgress(defaults: UserDefaults(suiteName: "scan-recovery-" + UUID().uuidString)!)
      progress.update { $0.step = "connect"; $0.navigationPath = ["install", "connect"] }
      let state = IOSPixelScannerState()
      var preview: AVCaptureVideoPreviewLayer?
      ScannerController.simulatedPreview = { preview = $0 }
      defer { ScannerController.simulatedPreview = nil }
      let window = UIWindow(windowScene: scene)
      window.rootViewController = UIHostingController(rootView: IOSOnboarding(model: model, progress: progress, scanner: state))
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(500))
      let first = try XCTUnwrap(preview)
      let session = try XCTUnwrap(first.session)
      NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: session,
        userInfo: [AVCaptureSessionInterruptionReasonKey: AVCaptureSession.InterruptionReason.videoDeviceInUseByAnotherClient.rawValue])
      try await Task.sleep(for: .milliseconds(250))
      XCTAssertEqual(state.cameraFailure, .unavailable)
      XCTAssertEqual(progress.record?.step, "connect")
      state.retry()
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertNil(state.cameraFailure)
      let retried = try XCTUnwrap(preview)
      XCTAssertFalse(retried === first)
      XCTAssertTrue((retried.delegate as? UIView)?.window === window)
    }
  }
  #endif

  func testFirstRunUsesOneNativeStackAndRestoresOnlyVisitedPages() async throws {
    try await withModel("onboarding.connected") { model, _ in
      await model.open()
      let pairedProgress = IOSFirstRunProgress(defaults: UserDefaults(suiteName: "catalog-first-run-paired-" + UUID().uuidString)!)
      pairedProgress.resolve(legacyDone: false, paired: true)
      XCTAssertEqual(IOSOnboardingNavigation(record: pairedProgress.record).path, [.photos])
      let defaults = UserDefaults(suiteName: "catalog-first-run-route-" + UUID().uuidString)!
      let progress = IOSFirstRunProgress(defaults: defaults)
      progress.update { $0.step = "welcome" }
      let route = IOSOnboardingNavigation(record: progress.record)
      let scanner = IOSPixelScannerState()
      let host = UIHostingController(rootView: IOSOnboarding(model: model, progress: progress, scanner: scanner, navigation: route))
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
      window.rootViewController = host; window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(350))
      let nav = try XCTUnwrap(firstRunNavigation(host))
      let bar = nav.navigationBar
      XCTAssertTrue(bar.isHidden)
      for (index, step) in IOSOnboarding.Step.allCases.dropFirst().enumerated() {
        if step == .connected { scanner.payload = "synthetic-completed-code"; scanner.connectionCompleted = true }
        route.go(step)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(firstRunNavigation(host) === nav)
        XCTAssertTrue(nav.navigationBar === bar)
        XCTAssertFalse(bar.isHidden, step.rawValue)
        XCTAssertFalse(try XCTUnwrap(nav.topViewController).navigationItem.hidesBackButton)
        XCTAssertEqual(nav.viewControllers.count, index + 2, step.rawValue)
        XCTAssertEqual(progress.record?.step, step.rawValue)
        XCTAssertEqual(IOSOnboardingNavigation(record: IOSFirstRunProgress(defaults: defaults).record).path, route.path)
      }
      for expected in IOSOnboarding.Step.allCases.dropLast().reversed() {
        XCTAssertNotNil(nav.popViewController(animated: false))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(route.step, expected)
        XCTAssertEqual(progress.record?.step, expected.rawValue)
        XCTAssertEqual(bar.isHidden, expected == .welcome)
        if expected == .connect {
          XCTAssertNil(scanner.payload, "Returning to Scan must not replay a completed code or remain on Connecting")
          XCTAssertFalse(scanner.connectionCompleted)
        }
      }
      // A paired receiver skips setup without inventing destinations behind Photos.
      route.go(.photos)
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertEqual(nav.viewControllers.count, 2)
      XCTAssertEqual(progress.record?.navigationPath, ["photos"])
      let restored = IOSOnboardingNavigation(record: IOSFirstRunProgress(defaults: defaults).record)
      XCTAssertEqual(restored.path, [.photos])
      XCTAssertNotNil(nav.popViewController(animated: false))
      try await Task.sleep(for: .milliseconds(150))
      XCTAssertEqual(route.step, .welcome)
      XCTAssertTrue(bar.isHidden)
    }
  }

  func testFirstRunPendingActionKeepsNativeBackAndContentGeometry() async throws {
    try await withModel("onboarding.connected") { model, _ in
      await model.open()
      let progress = IOSFirstRunProgress(defaults: UserDefaults(suiteName: "catalog-first-run-pending-" + UUID().uuidString)!)
      progress.update { $0.step = "photos"; $0.receiver = model.pairing?.receiverID }
      let route = IOSOnboardingNavigation(record: progress.record)
      let host = UIHostingController(rootView: IOSOnboarding(model: model, progress: progress, navigation: route))
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
      let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
      window.rootViewController = host; window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(350))
      let nav = try XCTUnwrap(firstRunNavigation(host))
      let page = try XCTUnwrap(nav.topViewController)
      let item = page.navigationItem
      let barFrame = nav.navigationBar.convert(nav.navigationBar.bounds, to: window)
      let safeTop = page.view.safeAreaInsets.top
      let visit = route.revision
      route.working = true
      try await Task.sleep(for: .milliseconds(200))
      XCTAssertTrue(nav.topViewController === page)
      XCTAssertTrue(nav.navigationBar.topItem === item)
      XCTAssertFalse(item.hidesBackButton)
      XCTAssertFalse(nav.navigationBar.isHidden)
      XCTAssertEqual(nav.navigationBar.convert(nav.navigationBar.bounds, to: window), barFrame)
      XCTAssertEqual(page.view.safeAreaInsets.top, safeTop, accuracy: 0.5)
      // Back remains system-owned while the async operation is outstanding.
      XCTAssertNotNil(nav.popViewController(animated: false))
      try await Task.sleep(for: .milliseconds(150))
      XCTAssertEqual(route.step, .connected)
      XCTAssertFalse(route.working)
      XCTAssertFalse(route.owns(.photos, revision: visit))
      route.go(.photos)
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertFalse(route.owns(.photos, revision: visit), "A result from the previous visit cannot push the new visit")
      XCTAssertEqual(progress.record?.step, "photos")
      let returningPage = try XCTUnwrap(nav.topViewController)
      let returningItem = returningPage.navigationItem
      route.working = true
      try await Task.sleep(for: .milliseconds(500))
      XCTAssertTrue(nav.navigationBar.topItem === returningItem)
      XCTAssertFalse(returningItem.hidesBackButton)
      XCTAssertEqual(nav.navigationBar.convert(nav.navigationBar.bounds, to: window), barFrame)
      XCTAssertEqual(returningPage.view.safeAreaInsets.top, safeTop, accuracy: 0.5)
      route.working = false
      // The native stack performs the same forward transition after permission
      // completes; the pending state never removes its source navigation item.
      withAnimation { route.go(.choose) }
      try await Task.sleep(for: .milliseconds(500))
      XCTAssertTrue(firstRunNavigation(host) === nav)
      XCTAssertEqual(progress.record?.step, "choose")
      XCTAssertFalse(try XCTUnwrap(nav.topViewController).navigationItem.hidesBackButton)
      XCTAssertEqual(nav.navigationBar.convert(nav.navigationBar.bounds, to: window), barFrame)
      XCTAssertNotNil(nav.popViewController(animated: true))
      try await Task.sleep(for: .milliseconds(500))
      XCTAssertTrue(nav.topViewController === returningPage)
      XCTAssertTrue(nav.navigationBar.topItem === returningItem)
      XCTAssertEqual(progress.record?.step, "photos")
      XCTAssertEqual(nav.navigationBar.convert(nav.navigationBar.bounds, to: window), barFrame)
    }
  }

  private func firstRunNavigation(_ controller: UIViewController) -> UINavigationController? {
    if let nav = controller as? UINavigationController { return nav }
    return controller.children.lazy.compactMap { self.firstRunNavigation($0) }.first
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
