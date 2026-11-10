import Photos
import SwiftUI
import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class AlbumBrowseNavigationTests: XCTestCase {
  func testPushedSupportingPageFollowsLiveTraitsLocaleAndContentWithoutResettingSearch() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let state = LiveSupportingEnvironmentState(), observed = LiveSupportingEnvironmentObservation()
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    window.rootViewController = UIHostingController(rootView: LiveSupportingEnvironmentFixture(state: state))
    window.makeKeyAndVisible(); defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(400))
    func find<T>(_ parent: UIViewController?, type: T.Type) -> T? {
      guard let parent else { return nil }
      if let value = parent as? T { return value }
      return parent.children.compactMap { find($0, type: type) }.first
    }
    let navigation = try XCTUnwrap(find(window.rootViewController, type: IOSNativeNavigationController.self))
    let fixture = ScopeCatalogFixture(id: "settings.scope.albums")
    navigation.pushPage(DuckSettingsPage(title: Text("scope_albums_title"), content: AnyView(
      BackupScopeEditor(destination: .albums, store: fixture.store, model: fixture.albums)
        .background(LiveSupportingEnvironmentProbe(observed: observed)))), animated: false)
    try await Task.sleep(for: .milliseconds(500))
    let page = try XCTUnwrap(navigation.topViewController)
    XCTAssertEqual(page.navigationItem.title, "Albums")
    let search = try XCTUnwrap(page.navigationItem.searchController)
    search.searchBar.becomeFirstResponder()
    try await Task.sleep(for: .milliseconds(300))
    search.searchBar.searchTextField.insertText("Family")
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(page.navigationItem.searchController?.searchBar.text, "Family")
    let initialSize = observed.size
    navigation.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertEqual(observed.size, .accessibility5, "Pushed SwiftUI content follows live native traits")
    state.locale = Locale(identifier: "zh-Hans")
    state.author = "Updated support content"
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertTrue(navigation.topViewController === page)
    XCTAssertEqual(navigation.viewControllers.count, 2)
    XCTAssertEqual(navigation.hostingEnvironment?.locale.identifier, "zh-Hans")
    XCTAssertEqual(navigation.hostingEnvironment?.duckReservedSettingsContent.authorText, "Updated support content")
    XCTAssertEqual(observed.locale, "zh-Hans")
    XCTAssertEqual(observed.author, "Updated support content")
    XCTAssertEqual(page.navigationItem.title, "相簿")
    XCTAssertEqual(page.navigationItem.searchController?.searchBar.text, "Family")
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    let attachment = XCTAttachment(image: image); attachment.name = "pushed-live-large-text-and-locale"; attachment.lifetime = .keepAlways; add(attachment)
    navigation.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertEqual(observed.size, initialSize)
    XCTAssertEqual(page.navigationItem.searchController?.searchBar.text, "Family")
  }

  func testNativeTabsKeepLibraryAnchorSelectionAndPushedSettings() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let state = NativeTabNavigationState()
    let grid = CalendarGridController()
    grid.assets = (0..<420).map { CalendarGridAsset(id: "tab-photo-\($0)", date: nil, aspect: 1) }
    let library = CalendarNavigationController(rootViewController: grid)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    window.rootViewController = UIHostingController(rootView: NativeTabNavigationFixture(state: state, library: library))
    window.makeKeyAndVisible(); defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(600))
    func find<T>(_ parent: UIViewController?, type: T.Type) -> T? {
      guard let parent else { return nil }
      if let value = parent as? T { return value }
      return parent.children.compactMap { find($0, type: type) }.first
    }
    let tabs = try XCTUnwrap(find(window.rootViewController, type: UITabBarController.self))
    XCTAssertEqual(tabs.viewControllers?.map { $0.tabBarItem.tag }, [0, 1, 3])
    XCTAssertEqual(tabs.view.convert(tabs.view.bounds, to: window), window.bounds)
    XCTAssertEqual(library.view.convert(library.view.bounds, to: window), window.bounds)
    grid.grid.setContentOffset(CGPoint(x: 0, y: grid.grid.contentSize.height * 0.5), animated: false)
    grid.selecting = true; grid.selected = ["tab-photo-210"]
    let anchor = grid.grid.contentOffset
    let retained = try XCTUnwrap(tabs.viewControllers).map(ObjectIdentifier.init)
    state.tab = IOSAppTab.settings.rawValue
    try await Task.sleep(for: .milliseconds(500))
    let settings = try XCTUnwrap(find(tabs.selectedViewController, type: IOSNativeNavigationController.self))
    settings.pushPage(DuckSettingsPage(title: Text("Help"), content: AnyView(Text("Help content"))), animated: false)
    let pushed = try XCTUnwrap(settings.topViewController)
    state.tab = IOSAppTab.library.rawValue
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertEqual(grid.grid.contentOffset.y, anchor.y, accuracy: 1)
    XCTAssertTrue(grid.selecting); XCTAssertEqual(grid.selected, ["tab-photo-210"])
    XCTAssertEqual(try XCTUnwrap(tabs.viewControllers).map(ObjectIdentifier.init), retained)
    XCTAssertTrue(tabs.delegate === grid.tabReselection)
    state.tab = IOSAppTab.settings.rawValue
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertTrue(settings.topViewController === pushed)
    XCTAssertEqual(settings.viewControllers.count, 2)
    if #available(iOS 26.0, *) { XCTAssertEqual(tabs.tabBarMinimizeBehavior, .never) }
  }

  func testEmbeddedNativeHostRestoresPickerNavigationItem() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
    window.rootViewController = UIHostingController(rootView: IOSNativeTabs(selection: .constant(IOSAppTab.settings.rawValue)) { tab in
      tab == .settings ? AnyView(IOSNativeNavigation(title: "Settings") { Text("Root") }) : AnyView(Text("Other tab"))
    })
    window.makeKeyAndVisible(); defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(300))
    func find<T>(_ parent: UIViewController?, type: T.Type) -> T? {
      guard let parent else { return nil }
      if let value = parent as? T { return value }
      return parent.children.compactMap { find($0, type: type) }.first
    }
    let navigation = try XCTUnwrap(find(window.rootViewController, type: IOSNativeNavigationController.self))
    let fixture = ScopeCatalogFixture(id: "settings.scope.albums")
    navigation.pushPage(DuckSettingsPage(title: Text("scope_albums_title"), content: AnyView(
      BackupScopeEditor(destination: .albums, store: fixture.store, model: fixture.albums))), animated: false)
    try await Task.sleep(for: .milliseconds(600))
    let picker = try XCTUnwrap(navigation.topViewController)
    XCTAssertEqual(picker.navigationItem.title, NSLocalizedString("scope_albums_title", comment: ""))
    XCTAssertNotNil(picker.navigationItem.searchController)
    let album = ScopeAlbum(id: "test", name: "Trips", count: 0, system: false, cover: nil)
    navigation.pushPage(DuckSettingsPage(title: Text(verbatim: album.name), content: AnyView(ScopeAlbumBrowser(album: album, store: fixture.store))), animated: false)
    try await Task.sleep(for: .milliseconds(600))
    let albumPage = try XCTUnwrap(navigation.topViewController)
    let grid = try XCTUnwrap(find(albumPage, type: CalendarGridController.self))
    XCTAssertTrue(grid.navigationItem === albumPage.navigationItem)
    XCTAssertFalse(albumPage.navigationItem === picker.navigationItem)
    let asset = CatalogLibraryAsset(14), library = PhotoLibraryModel()
    let item = IOSPreviewItem(asset: asset, frame: CGRect(x: 10, y: 160, width: 100, height: 100), poster: asset.previewImage)
    let viewer = NativeMediaViewer(item: item, session: MediaPreviewSession(asset: asset, library: library), close: {})
    presentMediaViewer(viewer, from: grid, poster: asset.previewImage)
    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(navigation.topViewController === viewer)
    let statusOwner = try XCTUnwrap(window.rootViewController as? MediaStatusBarRootController)
    XCTAssertTrue(statusOwner.childForStatusBarHidden === navigation)
    viewer.dismissViewer()
    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(navigation.topViewController === albumPage)
    XCTAssertTrue(grid.navigationItem === albumPage.navigationItem)
    navigation.popViewController(animated: false)
    try await Task.sleep(for: .milliseconds(600))
    XCTAssertTrue(navigation.topViewController === picker)
    XCTAssertNil(picker.navigationItem.rightBarButtonItem)
    XCTAssertEqual(navigation.navigationBar.topItem?.title, NSLocalizedString("scope_albums_title", comment: ""))
    XCTAssertNotNil(picker.navigationItem.searchController)
  }

  func testNativeRouteKeepsTheLatestRequestDuringPush() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    let navigation = IOSNativeNavigationController()
    navigation.installRoot(title: "Backup", content: AnyView(Text("Root")))
    window.rootViewController = navigation; window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(100))
    let destination: (String) -> UIViewController = { title in
      let page = UIViewController(); page.title = title; return page
    }
    navigation.updateRoute("all", destination: destination)
    navigation.updateRoute("attention", destination: destination)
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(navigation.topViewController?.title, "attention")
    XCTAssertEqual(navigation.viewControllers.count, 2)
    navigation.popViewController(animated: false)
    XCTAssertEqual(navigation.viewControllers.count, 1)
  }

  func testNativeSupportingHostRetainsTitleSearchAndRealPush() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    let navigation = IOSNativeNavigationController()
    let fixture = ScopeCatalogFixture(id: "settings.scope.albums")
    navigation.installRoot(title: "Settings", content: AnyView(Text("Root")))
    window.rootViewController = navigation; window.makeKeyAndVisible()
    defer { window.isHidden = true }
    navigation.pushPage(DuckSettingsPage(title: Text("scope_albums_title"), content: AnyView(
      BackupScopeEditor(destination: .albums, store: fixture.store, model: fixture.albums))), animated: false)
    let page = try XCTUnwrap(navigation.topViewController)
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(navigation.viewControllers.count, 2)
    XCTAssertEqual(page.navigationItem.title, NSLocalizedString("scope_albums_title", comment: ""))
    XCTAssertNotNil(page.navigationItem.searchController)
    XCTAssertTrue(navigation.navigationBar.topItem === page.navigationItem)
    let shot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    })
    shot.name = "native-pushed-album-picker"; shot.lifetime = .keepAlways; add(shot)
    XCTAssertFalse(navigation.isNavigationBarHidden)
    let edge = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
    XCTAssertTrue(edge.isEnabled)
    XCTAssertNotNil(edge.delegate)
    XCTAssertTrue(edge.delegate?.gestureRecognizerShouldBegin?(edge) ?? true)
  }

  func testUnavailableAlbumContentRetainsItsNativeChoice() async throws {
    let oldPhotos = BackupEnvironment.usesPhotoLibrary
    let oldSamples = BackupEnvironment.albumSamples
    BackupEnvironment.usesPhotoLibrary = false
    defer {
      BackupEnvironment.usesPhotoLibrary = oldPhotos
      BackupEnvironment.albumSamples = oldSamples
    }
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    for empty in [true, false] {
      BackupEnvironment.albumSamples = empty ? { _ in CatalogAssetCollection([]) } : nil
      let defaults = UserDefaults(suiteName: "album-bar-tests-\(UUID().uuidString)")!
      let store = BackupScopeStore(defaults: defaults)
      store.save(BackupScopeRule(types: [.photo], restrictAlbums: true, albums: []))
      let album = ScopeAlbum(id: "missing-album", name: "Family", count: 0, system: false, cover: nil)
      let window = UIWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      window.rootViewController = UIHostingController(rootView: NavigationStack { ScopeAlbumBrowser(album: album, store: store) })
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .milliseconds(500))
      func find(_ controller: UIViewController?) -> CalendarGridController? {
        guard let controller else { return nil }
        if let grid = controller as? CalendarGridController { return grid }
        return controller.children.compactMap { find($0) }.first
      }
      let grid = try XCTUnwrap(find(window.rootViewController))
      let item = try XCTUnwrap(grid.navigationItem.rightBarButtonItem)
      XCTAssertFalse(try XCTUnwrap(grid.navigationController).isNavigationBarHidden)
      XCTAssertNotNil(grid.navigationItem.backAction)
      XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item, for: nil))
      try await Task.sleep(for: .milliseconds(1500))
      XCTAssertTrue(store.rule.choosesAlbum(album.id))
      XCTAssertFalse(grid.navigationItem.rightBarButtonItem === item)
      XCTAssertEqual(grid.navigationItem.rightBarButtonItem?.accessibilityLabel, NSLocalizedString("scope_album_deselect", comment: ""))
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      })
      attachment.name = empty ? "album-native-empty-content" : "album-native-denied-content"
      attachment.lifetime = .keepAlways; add(attachment)
    }
  }

  func testSavedAlbumChoiceKeepsItsNativeItemAndNavigationOwner() throws {
    let grid = CalendarGridController()
    grid.browseOnly = true
    let navigation = CalendarNavigationController(rootViewController: grid)
    grid.loadViewIfNeeded()
    var selected = false
    var backs = 0
    func update() {
      grid.configureBrowseNavigation(CalendarBrowseNavigation(title: "Family", selected: selected,
        back: { backs += 1 }, toggle: { selected.toggle() }))
    }
    update()
    let item = try XCTUnwrap(grid.navigationItem.rightBarButtonItem)
    XCTAssertNil(item.customView, "The system bar owns the button and its interaction")
    XCTAssertEqual(grid.navigationItem.title, "Family")
    XCTAssertNil(grid.navigationItem.leftBarButtonItem, "A content title must not replace system Back")
    XCTAssertEqual(item.accessibilityLabel, NSLocalizedString("scope_album_choose", comment: ""))
    XCTAssertTrue(item.changesSelectionAsPrimaryAction)
    XCTAssertFalse(item.isSelected)
    XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item, for: nil))
    update()
    XCTAssertTrue(selected)
    let deselect = try XCTUnwrap(grid.navigationItem.rightBarButtonItem)
    XCTAssertFalse(deselect === item)
    XCTAssertEqual(deselect.accessibilityLabel, NSLocalizedString("scope_album_deselect", comment: ""))
    XCTAssertTrue(deselect.isSelected)
    XCTAssertEqual(grid.navigationItem.backAction?.title, "")
    if #available(iOS 26.0, *) { XCTAssertEqual(deselect.identifier, item.identifier) }
    XCTAssertEqual(navigation.viewControllers.count, 1, "Choosing the album never navigates or dismisses")
    grid.updateChrome()
    XCTAssertFalse(navigation.isNavigationBarHidden, "Browse mode retains the owning native navigation bar")
    XCTAssertEqual(backs, 0)
  }
}

@MainActor private final class NativeTabNavigationState: ObservableObject {
  @Published var tab = IOSAppTab.library.rawValue
}
private struct NativeTabNavigationFixture: View {
  @ObservedObject var state: NativeTabNavigationState
  let library: CalendarNavigationController
  var body: some View {
    IOSNativeTabs(selection: $state.tab) { tab in
      switch tab {
      case .library: AnyView(NativeTabLibraryPage(navigation: library))
      case .backup: AnyView(Text("Backup"))
      case .settings: AnyView(IOSNativeNavigation(title: "Settings") { Text("Settings") })
      }
    }
  }
}
private struct NativeTabLibraryPage: UIViewControllerRepresentable {
  let navigation: CalendarNavigationController
  func makeUIViewController(context: Context) -> CalendarNavigationController { navigation }
  func updateUIViewController(_ controller: CalendarNavigationController, context: Context) {}
}

@MainActor private final class LiveSupportingEnvironmentState: ObservableObject {
  @Published var locale = Locale(identifier: "en_US")
  @Published var author: String?
}
@MainActor private final class LiveSupportingEnvironmentObservation {
  var size: DynamicTypeSize?
  var locale: String?
  var author: String?
}
private struct LiveSupportingEnvironmentFixture: View {
  @ObservedObject var state: LiveSupportingEnvironmentState
  var body: some View {
    IOSNativeTabs(selection: .constant(IOSAppTab.settings.rawValue)) { tab in
      tab == .settings ? AnyView(IOSNativeNavigation(title: "Settings") { Text("Settings") }) : AnyView(Text("Other"))
    }
    .environment(\.locale, state.locale)
    .environment(\.duckReservedSettingsContent, DuckReservedSettingsContent(authorText: state.author))
  }
}
private struct LiveSupportingEnvironmentProbe: View {
  let observed: LiveSupportingEnvironmentObservation
  @Environment(\.dynamicTypeSize) private var size
  @Environment(\.locale) private var locale
  @Environment(\.duckReservedSettingsContent) private var reserved
  var body: some View {
    Color.clear
      .onChange(of: size, initial: true) { _, value in observed.size = value }
      .onChange(of: locale, initial: true) { _, value in observed.locale = value.identifier }
      .onChange(of: reserved.authorText, initial: true) { _, value in observed.author = value }
  }
}
