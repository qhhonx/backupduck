import AppKit
import SwiftUI
import XCTest
@testable import BackupDuckCatalog

@MainActor final class MacNativeControlsTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func tearDown() {
    windows.forEach { $0.orderOut(nil); $0.contentViewController = nil }
    windows = []
    super.tearDown()
  }

  // Native search may finish its width transition after the editing notification.
  private func settle() async { try? await Task.sleep(for: .milliseconds(600)) }

  private func mount<V: View>(_ content: V, width: CGFloat = 1180) async -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 740),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.contentViewController = NSHostingController(rootView: NavigationSplitView {
      List { Text("Settings") }
    } detail: { content }.frame(width: width, height: 740))
    windows.append(window)
    window.makeKeyAndOrderFront(nil)
    await settle()
    return window
  }

  private func search(in window: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws -> NSSearchToolbarItem {
    let items = window.toolbar?.items ?? []
    print("Native toolbar items: \(items.map { String(describing: type(of: $0)) + ":" + $0.itemIdentifier.rawValue })")
    let searches = items.compactMap { $0 as? NSSearchToolbarItem }
    XCTAssertEqual(searches.count, 1, "Exactly one native search item owns the toolbar search", file: file, line: line)
    return try XCTUnwrap(searches.first, file: file, line: line)
  }

  func testWorkspaceRetainsSettingsDetailAcrossDestinations() async throws {
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == "records.toolbar-all" })
    let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    await model.open()
    var routesOpened = 0
    var lifetimes: [SettingsDetailLifetime] = []
    let window = await mount(MacWorkspace(model: model, library: PhotoLibraryModel(), initialDestination: .settings,
      openInitialSettingsDetail: { navigator in
        routesOpened += 1
        navigator.open(DuckSettingsPage(title: Text("Retained detail"), content: AnyView(
          RetainedSettingsDetail { lifetimes.append($0) })))
      }))
    let lifetime = try XCTUnwrap(lifetimes.first)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowTransfers"), object: nil)
    await settle()
    XCTAssertEqual(window.title, NSLocalizedString("records_title", comment: ""))
    XCTAssertFalse(window.toolbar?.items.contains { $0.view?.accessibilityIdentifier() == "settings.secondary.back" } == true)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowSettings"), object: nil)
    await settle()
    XCTAssertEqual(routesOpened, 1, "Returning must not reconstruct the settings navigator")
    XCTAssertTrue(lifetimes.allSatisfy { $0 === lifetime }, "The pushed detail keeps its native and SwiftUI state")
    XCTAssertEqual(window.title, "Retained detail")
    model.stop()
  }

  func testInactiveRetainedSearchCannotOwnToolbar() async throws {
    let state = SearchState()
    let activity = WorkspaceActivity()
    let window = await mount(RetainedSearchHost(state: state, activity: activity))
    _ = try search(in: window)
    state.text = "Family"
    activity.active = false
    await settle()
    XCTAssertTrue(window.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.isEmpty ?? true)
    activity.active = true
    await settle()
    _ = try search(in: window)
    XCTAssertEqual(state.text, "Family")
  }

  func testNativeSearchIsConfiguredBeforeToolbarInsertion() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 740),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    windows.append(window)
    let toolbar = NSToolbar(identifier: "initial-search")
    let provider = NativeSearchProvider()
    toolbar.delegate = provider; window.toolbar = toolbar
    let probe = MacToolbarSearchView(frame: .zero)
    window.contentView?.addSubview(probe)
    var configuredBeforeInsertion = false
    let observation = NotificationCenter.default.addObserver(forName: NSToolbar.willAddItemNotification,
      object: toolbar, queue: .main) { note in
      MainActor.assumeIsolated {
        guard let item = note.userInfo?.values.compactMap({ $0 as? NSSearchToolbarItem }).first else { return }
        configuredBeforeInsertion = item.searchField.constraints.contains {
          $0.identifier == "BackupDuck.search.compact" && $0.isActive && $0.priority == .defaultLow
        } && item.preferredWidthForSearchField == MacBrowsingToolbarMetrics.searchWidth
      }
    }
    defer { NotificationCenter.default.removeObserver(observation) }
    toolbar.insertItem(withItemIdentifier: provider.item.itemIdentifier, at: 0)
    XCTAssertTrue(configuredBeforeInsertion, "The first native toolbar layout must already have compact search geometry")
  }

  func testBrowsingTitleKeepsNativeGeometryUntilDateArrives() async throws {
    let range = MacVisibleRange()
    let title = "Folder title"
    let window = await mount(Text("Photos").modifier(MacLibraryWindowChrome(title: title, range: range, fixed: nil)))
    func titleField(_ view: NSView?) -> NSTextField? {
      guard let view else { return nil }
      if let field = view as? NSTextField, field.stringValue == title { return field }
      return view.subviews.lazy.compactMap { titleField($0) }.first
    }
    let before = try XCTUnwrap(titleField(window.contentView?.superview))
    let frame = before.convert(before.bounds, to: nil), font = before.font?.pointSize
    XCTAssertEqual(window.subtitle, "\u{00a0}", "Unknown date reserves geometry without fabricating content")
    range.title = "October 10–19, 2026"
    await settle()
    let after = try XCTUnwrap(titleField(window.contentView?.superview))
    XCTAssertEqual(after.convert(after.bounds, to: nil).minY, frame.minY, accuracy: 0.5)
    XCTAssertEqual(after.font?.pointSize, font)
    XCTAssertEqual(window.subtitle, range.title)
  }

  func testHelpUsesNativeToolbarSearch() async throws {
    let window = await mount(HelpCenter())
    _ = try search(in: window)
  }

  func testAlbumsUseNativeToolbarSearch() async throws {
    let fixture = ScopeCatalogFixture(id: "settings.scope.albums")
    let window = await mount(BackupScopeEditor(destination: .albums, store: fixture.store, model: fixture.albums))
    _ = try search(in: window)
  }

  func testFoldersUseNativeToolbarSearch() async throws {
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == "folders.viewer" })
    let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    let folders = FolderSources(backup: model)
    FolderCatalog.install("folders.viewer", folders: folders, sheet: nil)
    let window = await mount(FolderSourcesPage(folders: folders, backup: model))
    _ = try search(in: window)
  }

  func testHistoryUsesNativeToolbarSearch() async throws {
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == "records.toolbar-all" })
    let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    await model.open()
    let window = await mount(MacWorkspace(model: model, library: PhotoLibraryModel(), initialDestination: .transfers))
    _ = try search(in: window)
    model.stop()
  }

  func testSearchStartsCompactAndExpandsOnlyForEditing() async throws {
    let model = SearchState()
    let window = await mount(SearchHost(state: model))
    let item = try search(in: window)
    let compact = try XCTUnwrap(item.searchField.constraints.first { $0.identifier == "BackupDuck.search.compact" })
    func assertNativeCompact(file: StaticString = #filePath, line: UInt = #line) throws {
      let field = item.searchField
      let cell = try XCTUnwrap(field.cell as? NSSearchFieldCell, file: file, line: line)
      let glyph = try XCTUnwrap(cell.searchButtonCell?.image, file: file, line: line)
      // The low-priority field preference is not the native toolbar's minimum.
      // A compact item fits the system's own one-button-height footprint.
      // The wide editing field cannot satisfy this geometric assertion.
      XCTAssertLessThanOrEqual(field.frame.width, field.frame.height + 1, file: file, line: line)
      // The toolbar owns the collapsed button. The cell reports positions for
      // the expanded search field even when the toolbar is showing its icon.
      XCTAssertGreaterThan(glyph.size.width, 0, file: file, line: line)
      XCTAssertGreaterThan(glyph.size.height, 0, file: file, line: line)
      XCTAssertLessThanOrEqual(glyph.size.width, field.bounds.width, file: file, line: line)
      XCTAssertLessThanOrEqual(glyph.size.height, field.bounds.height, file: file, line: line)
      XCTAssertNil(field.currentEditor(), file: file, line: line)
    }
    XCTAssertEqual(item.preferredWidthForSearchField, MacBrowsingToolbarMetrics.searchWidth)
    XCTAssertTrue(compact.isActive, "Initial search must be a compact magnifier")
    try assertNativeCompact()
    XCTAssertNil(item.searchField.currentEditor())
    XCTAssertFalse(model.presented)
    item.beginSearchInteraction()
    await settle()
    XCTAssertTrue(compact.isActive, "The compact preference stays mounted throughout the native transition")
    XCTAssertEqual(compact.priority, .defaultLow, "The compact preference must yield to AppKit's editing width")
    XCTAssertNotNil(item.searchField.currentEditor())
    XCTAssertGreaterThan(item.searchField.frame.width, compact.constant * 2)
    XCTAssertLessThanOrEqual(item.searchField.frame.width, MacBrowsingToolbarMetrics.searchWidth + 1)
    item.endSearchInteraction()
    await settle()
    XCTAssertTrue(compact.isActive, "Finishing search must restore the compact representation")
    try assertNativeCompact()
  }

  func testContentClickCallbackEndsEditingWithoutConsumingInput() async throws {
    let model = SearchState()
    let window = await mount(SearchHost(state: model))
    let item = try search(in: window)
    item.beginSearchInteraction()
    await settle()
    let editor = try XCTUnwrap(item.searchField.currentEditor() as? NSTextView)
    editor.insertText("Family", replacementRange: NSRange(location: 0, length: 0))
    await settle()
    let observer = try XCTUnwrap(window.contentView?.gestureRecognizers.first {
      String(describing: type(of: $0)) == "MacSearchContentClick"
    })
    XCTAssertFalse(observer.delaysPrimaryMouseButtonEvents)
    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 600, y: 300),
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    XCTAssertTrue(window.contentLayoutRect.contains(event.locationInWindow))
    observer.mouseDown(with: event)
    await settle()
    XCTAssertNil(item.searchField.currentEditor())
    XCTAssertEqual(model.text, "Family", "Ending content editing must retain the active filter")
    XCTAssertEqual(item.searchField.stringValue, "", "The compact native item must not clip a hidden query")
    XCTAssertLessThanOrEqual(item.searchField.frame.width, item.searchField.frame.height + 1)
    XCTAssertTrue(item.searchField.constraints.first { $0.identifier == "BackupDuck.search.compact" }?.isActive == true,
      "Losing focus must also collapse the search presentation")
    XCTAssertNotEqual(observer.state, .began)
    XCTAssertNotEqual(observer.state, .changed)
    item.beginSearchInteraction()
    await settle()
    XCTAssertEqual(item.searchField.stringValue, "Family", "Reopening must retain the current query")
    let reopenedEditor = try XCTUnwrap(item.searchField.currentEditor() as? NSTextView)
    reopenedEditor.selectAll(nil)
    reopenedEditor.deleteBackward(nil)
    await settle()
    XCTAssertEqual(model.text, "", "Text deletion must work after reopening")
  }

  func testProgrammaticSearchPresentationFocusesNativeSearch() async throws {
    let model = SearchState()
    let window = await mount(SearchHost(state: model))
    let item = try search(in: window)
    model.presented = true
    await settle()
    XCTAssertNotNil(item.searchField.currentEditor())
    item.endSearchInteraction()
    await settle()
    XCTAssertNil(item.searchField.currentEditor())
  }

  func testExistingQueryStartsCompactAndReappearsWhenEditing() async throws {
    let model = SearchState()
    model.text = "Family"
    let window = await mount(SearchHost(state: model))
    let item = try search(in: window)
    XCTAssertEqual(model.text, "Family")
    XCTAssertEqual(item.searchField.stringValue, "")
    item.beginSearchInteraction()
    await settle()
    XCTAssertEqual(model.text, "Family")
    XCTAssertEqual(item.searchField.stringValue, "Family")
    window.makeFirstResponder(nil)
    await settle()
    XCTAssertEqual(model.text, "Family", "Moving focus out of the search field must retain the query")
    XCTAssertEqual(item.searchField.stringValue, "")
    XCTAssertTrue(item.searchField.constraints.first { $0.identifier == "BackupDuck.search.compact" }?.isActive == true)
    XCTAssertLessThanOrEqual(item.searchField.frame.width, item.searchField.frame.height + 1)
  }

  func testRestoredExpandedSearchShowsItsExistingQuery() async throws {
    let model = SearchState()
    model.text = "Family"
    model.presented = true
    let window = await mount(SearchHost(state: model))
    let item = try search(in: window)
    XCTAssertEqual(model.text, "Family")
    XCTAssertEqual(item.searchField.stringValue, "Family", "Restored expanded search must display its active filter")
  }

  func testAlbumToolbarIdentitySurvivesSavedScopeChanges() async throws {
    let fixture = ScopeCatalogFixture(id: "settings.scope.albums")
    let album = try XCTUnwrap(fixture.albums.albums.first)
    let window = await mount(MacScopeAlbumBrowser(album: album, store: fixture.store, library: PhotoLibraryModel()))
    let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "settings.album.selection" })
    for _ in 0..<4 {
      fixture.store.save(fixture.store.rule.toggling(album: album.id, name: album.name))
      await settle()
      XCTAssertTrue(window.toolbar?.items.contains(where: { $0 === item }) == true,
        "Saved choice changes must update the existing native toolbar item")
    }
  }

  func testNativeSearchCancellationReleasesFocus() async throws {
    let model = SearchState()
    let window = await mount(SearchHost(state: model))
    let item = try search(in: window)
    item.beginSearchInteraction()
    await settle()
    XCTAssertNotNil(item.searchField.currentEditor())
    let editor = try XCTUnwrap(item.searchField.currentEditor() as? NSTextView)
    editor.insertText("Family", replacementRange: NSRange(location: 0, length: 0))
    await settle()
    XCTAssertEqual(model.text, "Family")
    let handled = window.firstResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil)
    await settle()
    print("Cancel handled=\(String(describing: handled)), text=\(model.text), editing=\(item.searchField.currentEditor() != nil)")
    XCTAssertEqual(model.text, "")
    XCTAssertNil(item.searchField.currentEditor())
    XCTAssertTrue(item.searchField.constraints.first { $0.identifier == "BackupDuck.search.compact" }?.isActive == true)
  }
}

@MainActor private final class SearchState: ObservableObject {
  @Published var text = ""
  @Published var presented = false
}

private struct SearchHost: View {
  @ObservedObject var state: SearchState
  var body: some View {
    Text("Search results: " + state.text)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { MacToolbarSearch(text: $state.text, presented: $state.presented) }
  }
}

@MainActor private final class SettingsDetailLifetime: ObservableObject {}
private struct RetainedSettingsDetail: View {
  @StateObject private var lifetime = SettingsDetailLifetime()
  let appeared: (SettingsDetailLifetime) -> Void
  var body: some View { Text("Detail content").onAppear { appeared(lifetime) } }
}
@MainActor private final class WorkspaceActivity: ObservableObject {
  @Published var active = true
}
private struct RetainedSearchHost: View {
  @ObservedObject var state: SearchState
  @ObservedObject var activity: WorkspaceActivity
  var body: some View {
    SearchHost(state: state).environment(\.macWorkspaceActive, activity.active)
      .opacity(activity.active ? 1 : 0)
  }
}

@MainActor private final class NativeSearchProvider: NSObject, NSToolbarDelegate {
  let item = NSSearchToolbarItem(itemIdentifier: .init("native-search"))
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { item }
}


/// Static compositions use real settings views in an unordered native window.
/// No system permission, source bookmark or production data is touched.
@MainActor final class MacSettingsOffscreenTests: XCTestCase {
  func testSettingsAndFilterEmptyCompositions() async throws {
    let output = URL(fileURLWithPath: "/private/tmp/backupduck-bd83-continuity/build/internal-docs/settings-final", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let previousModel = BackupEnvironment.activeModel, previousNotifier = BackupEnvironment.activeNotifier
    let previousAppearance = NSApp.appearance
    defer {
      BackupEnvironment.activeModel = previousModel; BackupEnvironment.activeNotifier = previousNotifier
      NSApp.appearance = previousAppearance
    }
    let scenarios = try Scenario.loadAll()
    for (name, page): (String, MacSettings.Page) in [("settings.advanced", .advanced), ("settings.folder-detail", .folders),
      ("settings.notifications.authorized", .autoBackup), ("settings.language", .language)] {
      let scenario = try XCTUnwrap(scenarios.first { $0.id == name } ?? scenarios.first { $0.id == "settings.autoBackup" })
      let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
      BackupEnvironment.activeModel = { model }
      let notifier = BackupNotifier(catalogAuthorization: .authorized)
      BackupEnvironment.activeNotifier = { notifier }
      await model.open()
      for dark in [false, true] {
        let folders = FolderSources(backup: model); folders.previewRows = []
        if page == .folders { FolderCatalog.install("settings.folder-detail", folders: folders, sheet: nil) }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: MacSettings(model: model, folders: folders, showFolders: {}, initialPage: page)
          .frame(width: 900, height: 760))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500)); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        XCTAssertFalse(window.isVisible)
        window.contentView = nil
      }
      model.stop()
    }
    let host = NSHostingView(rootView: MacGridFilterEmpty {}.frame(width: 700, height: 600)
      .background(DuckRole.background).accentColor(DuckRole.accentFill))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("grid-filter-empty.png"))
  }
}
