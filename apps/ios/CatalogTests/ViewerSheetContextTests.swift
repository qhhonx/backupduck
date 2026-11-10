import Photos
import SwiftUI
import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class ViewerSheetContextTests: XCTestCase {
  func testAlbumGridDisablesOnlyGridPinchInput() throws {
    let c = CalendarGridController()
    c.browseOnly = true
    c.allowsPinchZoom = false
    c.columns = 3
    c.assets = (0..<120).map { CalendarGridAsset(id: "album-\($0)", date: nil, aspect: 1) }
    c.browseNavigation = CalendarBrowseNavigation(title: "Album", selected: false, back: {}, toggle: {})
    c.loadViewIfNeeded()
    c.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    let pinch = try XCTUnwrap(c.grid.gestureRecognizers?.first { $0 is CalendarPinchGesture })
    XCTAssertFalse(pinch.isEnabled, "Disabled recognition must not take input from native scrolling")
    XCTAssertFalse(c.gestureRecognizerShouldBegin(pinch))
    XCTAssertTrue(c.grid.panGestureRecognizer.isEnabled)
    XCTAssertTrue(c.grid.isScrollEnabled)
    let otherGestures = (c.grid.gestureRecognizers ?? []).filter { $0 !== pinch }
    let inputStates = otherGestures.map(\.isEnabled)
    c.allowsPinchZoom = true
    XCTAssertTrue(pinch.isEnabled)
    c.allowsPinchZoom = false
    XCTAssertEqual(otherGestures.map(\.isEnabled), inputStates)
    let offset = c.grid.contentOffset
    c.pinch(UIPinchGestureRecognizer())
    XCTAssertNil(c.stage)
    XCTAssertEqual(c.columns, 3)
    XCTAssertEqual(c.grid.contentOffset, offset)
    var opened: String?
    c.onPreview = { asset, _ in opened = asset.id }
    c.collectionView(c.grid, didSelectItemAt: IndexPath(item: 6, section: 0))
    XCTAssertEqual(opened, c.assets[6].id, "Photo taps still reach the existing viewer")
    c.selecting = true
    c.collectionView(c.grid, didSelectItemAt: IndexPath(item: 7, section: 0))
    XCTAssertTrue(c.selected.contains(c.assets[7].id))
  }

  func testMainLibraryRetainsGridPinchInput() throws {
    let c = CalendarGridController()
    c.assets = (0..<120).map { CalendarGridAsset(id: "library-\($0)", date: nil, aspect: 1) }
    c.loadViewIfNeeded()
    c.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    let pinch = try XCTUnwrap(c.grid.gestureRecognizers?.first { $0 is CalendarPinchGesture })
    XCTAssertTrue(c.allowsPinchZoom)
    XCTAssertTrue(pinch.isEnabled)
    XCTAssertTrue(c.gestureRecognizerShouldBegin(pinch))
  }


  func testNativeBarRolesThroughHeldReturnAndReversal() async throws {
    let (window, _) = try window()
    defer { window.isHidden = true }
    for album in [false, true] {
      let source = CalendarGridController()
      source.browseOnly = album
      source.browseNavigation = album ? CalendarBrowseNavigation(title: "Trips", selected: true, back: {}, toggle: {}) : nil
      let navigation = CalendarNavigationController(rootViewController: source)
      window.rootViewController = navigation
      try await pause()
      let asset = SheetContextAsset(), library = PhotoLibraryModel()
      let frame = CGRect(x: 20, y: 150, width: 100, height: 100)
      library.previewFrame = { _ in frame }
      let item = IOSPreviewItem(asset: asset, frame: frame, poster: asset.previewImage)
      let viewer = NativeMediaViewer(item: item, session: MediaPreviewSession(asset: asset, library: library), close: {})
      presentMediaViewer(viewer, from: source, poster: asset.previewImage)
      try await wait { !viewer.openingTransition && viewer.viewIfLoaded?.window != nil }
      let transition = try XCTUnwrap(viewer.mediaTransition)
      let viewerNavigation = try XCTUnwrap(viewer.navigationController)
      func capture(_ state: String) {
        let shot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        shot.name = "native-bars-\(album ? "album" : "library")-\(state)"
        shot.lifetime = .keepAlways; add(shot)
      }
      capture("settled")
      viewer.prepareReturnChrome(); viewer.closing = true
      transition.beginInteractive(origin: CGPoint(x: 200, y: 350), center: CGPoint(x: 200, y: 400))
      viewerNavigation.dismiss(animated: true)
      transition.updateInteractive(CGPoint(x: 0, y: 100))
      try await pause(); capture("held")
      transition.updateInteractive(CGPoint(x: 0, y: 35))
      try await pause(); capture("reversed")
      XCTAssertTrue(transition.endInteractive(commit: false, velocity: -100))
      try await wait { viewerNavigation.presentingViewController != nil && viewerNavigation.transitionCoordinator == nil && !viewer.closing }
      XCTAssertTrue(viewer.pager.isScrollEnabled)
      XCTAssertFalse(viewer.closing)
      capture("cancelled")
      viewer.dismissViewer()
      try await wait { viewerNavigation.presentingViewController == nil }
      XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled == true)
    }
  }

  func testOrdinarySourceKeepsTheFullScreenPresentation() async throws {
    let (window, root) = try window()
    defer { window.isHidden = true }
    let asset = SheetContextAsset(), library = PhotoLibraryModel()
    let item = IOSPreviewItem(asset: asset, frame: CGRect(x: 20, y: 150, width: 100, height: 100), poster: asset.previewImage)
    let viewer = NativeMediaViewer(item: item, session: MediaPreviewSession(asset: asset, library: library), close: {})
    presentMediaViewer(viewer, from: root, poster: asset.previewImage)
    try await wait { !viewer.openingTransition && viewer.viewIfLoaded?.window != nil }
    XCTAssertEqual(viewer.navigationController?.modalPresentationStyle, .overFullScreen)
    XCTAssertEqual(viewer.navigationController?.view.frame, window.bounds)
    viewer.dismissViewer()
    try await wait { root.presentedViewController == nil }
  }

  func testNativeGridAndViewerKeepIndependentSystemBars() async throws {
    let (window, _) = try window()
    defer { window.isHidden = true }
    let source = CalendarGridController()
    let navigation = CalendarNavigationController(rootViewController: source)
    window.rootViewController = navigation
    try await pause()
    let bar = navigation.navigationBar
    let asset = SheetContextAsset(), library = PhotoLibraryModel()
    let item = IOSPreviewItem(asset: asset, frame: CGRect(x: 20, y: 150, width: 100, height: 100), poster: asset.previewImage)
    let viewer = NativeMediaViewer(item: item, session: MediaPreviewSession(asset: asset, library: library), close: {})
    presentMediaViewer(viewer, from: source, poster: asset.previewImage)
    try await wait { !viewer.openingTransition && viewer.viewIfLoaded?.window != nil }
    let viewerNavigation = try XCTUnwrap(viewer.navigationController)
    XCTAssertFalse(viewerNavigation === navigation)
    XCTAssertTrue(navigation.navigationBar === bar)
    XCTAssertTrue(navigation.topViewController === source)
    XCTAssertNotNil(viewerNavigation.presentingViewController)
    // Use a distinct destination contrast so a background source write is observable.
    let viewerBar = viewerNavigation.navigationBar
    viewerBar.overrideUserInterfaceStyle = .light
    viewerBar.tintColor = DuckMedia.onMediaUIColor
    let style = viewerBar.overrideUserInterfaceStyle, tint = viewerBar.tintColor
    let hidden = viewerNavigation.isToolbarHidden
    source.selecting = true
    source.refreshSelection(); source.updateMediaHeader()
    XCTAssertEqual(viewerBar.overrideUserInterfaceStyle, style)
    XCTAssertEqual(viewerBar.tintColor, tint)
    XCTAssertEqual(viewerNavigation.isToolbarHidden, hidden)
    viewer.dismissViewer()
    try await wait { viewerNavigation.presentingViewController == nil }
    XCTAssertNil(navigation.delegate)
  }

  func testNavigationSheetKeepsItsBoundsThroughEntryAndReturn() async throws {
    let source = UIViewController(), sheet = MediaViewerNavigationController(rootViewController: source)
    try await exercise(sheet: sheet, source: source)
  }

  func testHostedHistorySheetKeepsItsBoundsThroughEntryAndReturn() async throws {
    let sheet = IOSHistoryNavigationController(model: BackupModel(), sheet: true, close: {})
    let history = try XCTUnwrap(sheet.topViewController)
    let source = UIViewController()
    history.addChild(source); history.view.addSubview(source.view); source.didMove(toParent: history)
    try await exercise(sheet: sheet, source: source)
  }

  func testRecordedHistoryFallbackKeepsTheSheetAndRecordedIdentity() async throws {
    let sheet = IOSHistoryNavigationController(model: BackupModel(), sheet: true, close: {})
    let history = try XCTUnwrap(sheet.topViewController)
    let source = UIViewController()
    history.addChild(source); history.view.addSubview(source.view); source.didMove(toParent: history)
    try await exercise(sheet: sheet, source: source, recorded: true)
  }

  func testSelectedReviewRetainsItsLiveBatchAfterPagingAndReturn() async throws {
    let (window, _) = try window()
    defer { window.isHidden = true }
    let sample = SelectionReviewSample(mode: "open", model: BackupModel(), appearance: .light)
    window.rootViewController = UINavigationController(rootViewController: sample)
    try await wait { sample.calendar.selectionReview?.viewIfLoaded?.window != nil }
    try await pause()
    let review = try XCTUnwrap(sample.calendar.selectionReview)
    let initial = review.selected
    review.onPreview(review)
    try await wait { (review.navigationController?.presentedViewController as? UINavigationController)?.topViewController is NativeMediaViewer }
    let navigation = try XCTUnwrap(review.navigationController?.presentedViewController as? UINavigationController)
    let viewer = try XCTUnwrap(navigation.topViewController as? NativeMediaViewer)
    try await wait { !viewer.openingTransition }
    let removed = viewer.session.current.asset.localIdentifier
    viewer.selectionButton.sendActions(for: .touchUpInside)
    XCTAssertEqual(review.selected, initial.subtracting([removed]))
    XCTAssertEqual(sample.library.selection, review.selected)
    XCTAssertEqual(viewer.session.count, initial.count, "A deselected item stays in the review batch until the sheet closes")
    let next = try XCTUnwrap(viewer.session.asset(at: 5))
    viewer.session.activate(next)
    viewer.dismissViewer()
    try await wait { navigation.presentingViewController == nil }
    XCTAssertTrue(sample.calendar.selectionReview === review)
    XCTAssertEqual(review.selected, initial.subtracting([removed]))
    XCTAssertEqual(sample.library.selection, review.selected)
    review.done()
  }

  func testSelectedReviewKeepsNavigationAndMarksStableDuringFlight() async throws {
    let (window, _) = try window()
    defer { window.isHidden = true }
    let sample = SelectionReviewSample(mode: "open", model: BackupModel(), appearance: .light)
    window.rootViewController = UINavigationController(rootViewController: sample)
    try await wait { sample.calendar.selectionReview?.viewIfLoaded?.window != nil }
    try await pause()
    let review = try XCTUnwrap(sample.calendar.selectionReview)
    let source = try XCTUnwrap(review.navigationController)
    let sourceBar = source.navigationBar.convert(source.navigationBar.bounds, to: window)
    review.onPreview(review)
    try await wait { (review.navigationController?.presentedViewController as? UINavigationController)?.topViewController is NativeMediaViewer }
    let navigation = try XCTUnwrap(review.navigationController?.presentedViewController as? UINavigationController)
    let viewer = try XCTUnwrap(navigation.topViewController as? NativeMediaViewer)
    try await wait { viewer.viewIfLoaded?.window != nil }
    var openingSamples = 0
    for _ in 0..<150 {
      if !viewer.openingTransition { break }
      viewer.layoutMedia()
      XCTAssertEqual(viewer.selectionButton.alpha, 0)
      XCTAssertTrue(viewer.pages.allSatisfy { $0.selectionMark.alpha == 0 })
      if let chrome = viewer.returnChromeViews.first {
        let captured = chrome.convert(chrome.bounds, to: window)
        XCTAssertEqual(captured.minY + DuckSpacing.small, sourceBar.minY, accuracy: 0.5,
          "The visible native chrome capture stays at the source bar's position")
        XCTAssertTrue(captured.contains(sourceBar), "The captured region includes the complete native bar")
      } else {
        XCTAssertEqual(navigation.navigationBar.convert(navigation.navigationBar.bounds, to: window).minY, sourceBar.minY, accuracy: 0.5)
      }
      XCTAssertEqual(source.navigationBar.convert(source.navigationBar.bounds, to: window), sourceBar)
      openingSamples += 1
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(viewer.openingTransition, "The presentation must complete")
    XCTAssertGreaterThan(openingSamples, 0, "The check must observe an active transition")
    XCTAssertEqual(viewer.selectionButton.alpha, 1)
    XCTAssertEqual(navigation.navigationBar.convert(navigation.navigationBar.bounds, to: window).minY, sourceBar.minY, accuracy: 0.5)
    viewer.dismissViewer()
    viewer.layoutMedia()
    XCTAssertEqual(viewer.selectionButton.alpha, 0, "A layout update cannot reshow marks during return")
    XCTAssertTrue(viewer.pages.allSatisfy { $0.selectionMark.alpha == 0 })
    try await wait { navigation.presentingViewController == nil }
    XCTAssertEqual(source.navigationBar.convert(source.navigationBar.bounds, to: window).minY, sourceBar.minY, accuracy: 0.5)
    review.done()
  }

  private func exercise(sheet: UIViewController, source: UIViewController, recorded: Bool = false) async throws {
    let (window, root) = try window()
    defer { window.isHidden = true }
    sheet.modalPresentationStyle = .pageSheet
    sheet.sheetPresentationController?.detents = [.large()]
    root.present(sheet, animated: false)
    try await pause()
    let originalFrame = sheet.view.convert(sheet.view.bounds, to: window)
    XCTAssertGreaterThan(originalFrame.minY, 0)
    let asset = SheetContextAsset(), library = PhotoLibraryModel()
    let frame = sheet.view.convert(CGRect(x: 20, y: 150, width: 100, height: 100), to: nil)
    library.previewFrame = { _ in frame }
    let session = MediaPreviewSession(asset: asset, library: library, poster: asset.previewImage, reviewAssets: [asset])
    let viewer: NativeMediaViewer
    if recorded {
      let job = BackupJob(id: 1, asset: .init(metadata: ["created_at_ms": "1600000000000"],
        kind: "photo", source_id: "missing-sheet-source", revision: "1", resources: [.init(filename: "recorded.jpg", size: 100)]),
        state: "received", confirmedBytes: 100, errorCode: nil, processing: "complete")
      viewer = IOSRecordedPhotoViewer(photo: HistoryPhoto(job: job), model: BackupModel(), close: {}).makeNativeViewer(frame: { _ in frame })
      XCTAssertEqual(viewer.recordedPhoto?.source, "missing-sheet-source")
    } else {
      viewer = NativeMediaViewer(item: IOSPreviewItem(asset: asset, frame: frame, poster: asset.previewImage), session: session, close: {})
    }
    presentMediaViewer(viewer, from: source, poster: asset.previewImage)
    try await wait { viewer.viewIfLoaded?.window != nil && !viewer.openingTransition }
    let navigation = try XCTUnwrap(viewer.navigationController)
    XCTAssertFalse(navigation === sheet)
    XCTAssertEqual(navigation.modalPresentationStyle, .custom)
    XCTAssertTrue(root.presentedViewController === sheet)
    XCTAssertEqual(navigation.view.convert(navigation.view.bounds, to: window), originalFrame)
    XCTAssertEqual(sheet.view.convert(sheet.view.bounds, to: window), originalFrame)
    XCTAssertTrue(sheet.isModalInPresentation, "The source sheet cannot dismiss while media owns downward input")
    XCTAssertNotNil(viewer.mediaTransition, "Sheet and ordinary sources reuse the same media transition")
    XCTAssertNil(viewer.preferredTransition)
    viewer.dismissViewer()
    try await wait { navigation.presentingViewController == nil }
    XCTAssertTrue(root.presentedViewController === sheet)
    XCTAssertFalse(sheet.isModalInPresentation, "Returning restores normal source-sheet dismissal")
    XCTAssertNil(navigation.delegate, "Source navigation delegates remain independent from media presentation")
    XCTAssertEqual(sheet.view.convert(sheet.view.bounds, to: window), originalFrame)
    root.dismiss(animated: false)
  }

  func testRepeatedEntryKeepsLiveGlassAndAlignedPhotoPlanes() async throws {
    let (window, _) = try window()
    defer { window.isHidden = true }
    for style in [UIUserInterfaceStyle.light, .dark] {
      window.overrideUserInterfaceStyle = style
      for portrait in [false, true] {
        let source = UIViewController(); source.view.backgroundColor = .systemTeal
        source.title = "Source grid"
        let navigation = UINavigationController(rootViewController: source)
        window.rootViewController = navigation
        try await pause()
        let asset = EntryChromeAsset(portrait: portrait), library = PhotoLibraryModel()
        let frame = CGRect(x: 16, y: window.safeAreaInsets.top + 48, width: 100, height: 100)
        let tile = UIImageView(image: asset.previewImage); tile.frame = frame; source.view.addSubview(tile)
        library.previewFrame = { _ in frame }
        for repetition in 0..<3 {
          let item = IOSPreviewItem(asset: asset, frame: frame, poster: asset.previewImage)
          let viewer = NativeMediaViewer(item: item, session: MediaPreviewSession(asset: asset,
            library: library, poster: asset.previewImage, reviewAssets: [asset]), close: {})
          presentMediaViewer(viewer, from: source, poster: asset.previewImage)
          try await wait { viewer.viewIfLoaded?.window != nil }
          let target = try XCTUnwrap(viewer.navigationController)
          let transition = try XCTUnwrap(viewer.mediaTransition)
          var samples = 0
          while viewer.openingTransition {
            XCTAssertTrue(viewer.returnChromeViews.isEmpty, "Entry must not freeze native glass pixels")
            XCTAssertEqual(target.view.alpha, 1)
            XCTAssertEqual(target.view.layer.presentation()?.opacity ?? 1, 1, accuracy: 0.001,
              "Native effect ancestors retain their natural opacity")
            XCTAssertFalse(target.isNavigationBarHidden)
            XCTAssertNotNil(transition.entrySourceCover)
            if transition.entryFlightViews.count == 2 {
              let first = transition.entryFlightViews[0], second = transition.entryFlightViews[1]
              let firstPosition = first.layer.presentation()?.position ?? first.layer.position
              let secondPosition = second.layer.presentation()?.position ?? second.layer.position
              let firstPoint = first.superview!.convert(firstPosition, to: window)
              let secondPoint = second.superview!.convert(secondPosition, to: window)
              XCTAssertEqual(firstPoint.x, secondPoint.x, accuracy: 0.75)
              XCTAssertEqual(firstPoint.y, secondPoint.y, accuracy: 0.75)
            }
            samples += 1
            try await Task.sleep(for: .milliseconds(16))
          }
          print("LIVE_ENTRY", style.rawValue, portrait, repetition, "samples", samples)
          XCTAssertGreaterThan(samples, 2)
          XCTAssertTrue(transition.entryFlightViews.isEmpty)
          XCTAssertNil(transition.entrySourceCover)
          try await Task.sleep(for: .milliseconds(300))
          viewer.dismissViewer()
          try await wait { target.presentingViewController == nil }
        }
      }
    }
  }

  private func window() throws -> (UIWindow, UIViewController) {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    let root = UIViewController(); root.view.backgroundColor = DuckRole.backgroundUIColor
    window.rootViewController = root; window.makeKeyAndVisible()
    return (window, root)
  }
  private func pause() async throws { try await Task.sleep(for: .milliseconds(700)) }
  private func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<150 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("Native sheet transition did not settle")
  }
}

private final class SheetContextAsset: PHAsset, PreviewSample, @unchecked Sendable {
  override var localIdentifier: String { "sheet-context-photo" }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { 800 }
  override var pixelHeight: Int { 600 }
  var previewImage: UIImage? {
    UIGraphicsImageRenderer(size: CGSize(width: 800,height: 600)).image { context in
      DuckRole.accentUIColor.setFill(); context.fill(CGRect(x: 0,y: 0,width: 800,height: 600))
    }
  }
  var previewFilename: String { "sheet-context.jpg" }
  var previewMetadata: [(String, String)] { [] }
}

private final class EntryChromeAsset: PHAsset, PreviewSample, @unchecked Sendable {
  let portrait: Bool
  init(portrait: Bool) { self.portrait = portrait; super.init() }
  override var localIdentifier: String { "entry-chrome-\(portrait)" }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var pixelWidth: Int { portrait ? 400 : 800 }
  override var pixelHeight: Int { portrait ? 1000 : 500 }
  var previewFilename: String { "synthetic-entry.jpg" }
  var previewMetadata: [(String, String)] { [] }
  var previewImage: UIImage? {
    UIGraphicsImageRenderer(size: CGSize(width: pixelWidth, height: pixelHeight)).image { context in
      UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      UIColor.systemPurple.setFill(); context.fill(CGRect(x: 0, y: 0, width: pixelWidth / 2, height: pixelHeight))
    }
  }
}
