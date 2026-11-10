import AppKit
import SwiftUI
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class SelectionBackupActionTests: XCTestCase {
  private struct PreparationFailure: LocalizedError {
    var errorDescription: String? { "Could not check the selected photos." }
  }

  func testPreparationFailureDoesNotRegisterOrReportAdded() async {
    let action = SelectionBackupAction()
    var submissions = 0
    await action.request(prepare: {
      XCTAssertTrue(action.busy)
      throw PreparationFailure()
    }, submit: {
      submissions += 1
      return true
    }, failure: { nil })
    XCTAssertEqual(submissions, 0)
    XCTAssertFalse(action.busy)
    XCTAssertFalse(action.added)
    XCTAssertFalse(action.confirmingRepeat)
    XCTAssertEqual(action.error, PreparationFailure().localizedDescription)
    await action.confirm()
    XCTAssertEqual(submissions, 0)
  }

  func testRepeatConfirmationRegistersCapturedSelectionOnce() async {
    let action = SelectionBackupAction()
    var selection: Set<String> = ["saved", "active"]
    let snapshot = selection
    var submitted: [Set<String>] = []
    await action.request(prepare: { true }, submit: {
      XCTAssertTrue(action.busy)
      submitted.append(snapshot)
      selection.subtract(snapshot)
      return true
    }, failure: { nil })
    XCTAssertTrue(action.confirmingRepeat)
    XCTAssertFalse(action.busy)
    XCTAssertTrue(submitted.isEmpty)
    selection.insert("selected-later")
    await action.confirm()
    await action.confirm()
    XCTAssertEqual(submitted, [snapshot])
    XCTAssertEqual(selection, ["selected-later"])
    XCTAssertTrue(action.added)
    XCTAssertFalse(action.confirmingRepeat)
    XCTAssertFalse(action.busy)
  }

  func testCancellationDiscardsPendingRegistration() async {
    let action = SelectionBackupAction()
    var submissions = 0
    await action.request(prepare: { true }, submit: {
      submissions += 1
      return true
    }, failure: { nil })
    action.cancel()
    await action.confirm()
    XCTAssertEqual(submissions, 0)
    XCTAssertFalse(action.confirmingRepeat)
    XCTAssertFalse(action.added)
    await action.request(prepare: { false }, submit: {
      submissions += 1
      return true
    }, failure: { nil })
    XCTAssertEqual(submissions, 1)
    XCTAssertTrue(action.added)
  }

  func testRegistrationFailureKeepsFailureVisibleAfterConfirmation() async {
    let action = SelectionBackupAction()
    await action.request(prepare: { true }, submit: { false }, failure: { "Receiver changed." })
    await action.confirm()
    XCTAssertEqual(action.error, "Receiver changed.")
    XCTAssertFalse(action.added)
    XCTAssertFalse(action.busy)
    XCTAssertFalse(action.confirmingRepeat)
  }

  func testNativeToolbarRetainsSelectionItemAndSymbolGeometry() async throws {
    let state = SelectionToolbarFixtureState()
    let host = NSHostingController(rootView: SelectionToolbarFixture(state: state))
    host.sizingOptions = []
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 600),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = host
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(100))
    let toolbar = try XCTUnwrap(window.toolbar)
    toolbar.isVisible = true
    window.contentView?.superview?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    func descendants(_ items: [NSToolbarItem]) -> [NSToolbarItem] {
      items.flatMap { item in [item] + ((item as? NSToolbarItemGroup).map { descendants($0.subitems) } ?? []) }
    }
    func matching(_ title: String) -> NSToolbarItem? {
      descendants(toolbar.items).first { $0.label == title || $0.title == title || $0.toolTip == title }
    }
    let backupTitle = NSLocalizedString("folders_back_up_selected", comment: "")
    let infoTitle = NSLocalizedString("photo_viewer_info", comment: "")
    print("Selection window visible=\(window.isVisible) toolbar=\(toolbar.isVisible) items=\(toolbar.visibleItems?.count ?? -1) size=\(window.frame)")
    print("Selection toolbar: " + descendants(toolbar.items).map {
      "\(type(of: $0)) label=\($0.label) title=\($0.title) help=\($0.toolTip ?? "") image=\($0.image != nil) view=\(String(describing: $0.view))"
    }.joined(separator: " | "))
    let backup = try XCTUnwrap(matching(backupTitle))
    let info = try XCTUnwrap(matching(infoTitle))
    let items = descendants(toolbar.items)
    XCTAssertLessThan(try XCTUnwrap(items.firstIndex { $0 === info }),
      try XCTUnwrap(items.firstIndex { $0 === backup }))
    let backupView = try XCTUnwrap(backup.view)
    let infoView = try XCTUnwrap(info.view)
    let views = items.compactMap(\.view)
    XCTAssertTrue(backupView.window === window)
    XCTAssertTrue(infoView.window === window)
    XCTAssertGreaterThan(backupView.bounds.width, 0)
    XCTAssertGreaterThan(infoView.bounds.width, 0)
    XCTAssertEqual(backupView.bounds.height, infoView.bounds.height, accuracy: 0.5)
    XCTAssertEqual(backupView.convert(backupView.bounds, to: nil).midY,
      infoView.convert(infoView.bounds, to: nil).midY, accuracy: 0.5)
    let frames = views.map { $0.convert($0.bounds, to: nil) }
    func assertStable(file: StaticString = #filePath, line: UInt = #line) {
      let current = descendants(toolbar.items)
      XCTAssertEqual(current.map(\.itemIdentifier), items.map(\.itemIdentifier), file: file, line: line)
      XCTAssertTrue(zip(current, items).allSatisfy { $0 === $1 }, file: file, line: line)
      XCTAssertTrue(backup.view === backupView, file: file, line: line)
      XCTAssertTrue(info.view === infoView, file: file, line: line)
      XCTAssertEqual(views.map { $0.convert($0.bounds, to: nil) }, frames, file: file, line: line)
    }
    for count in [1, 2, 12, 150, 0, 8] {
      state.count = count
      try await Task.sleep(for: .milliseconds(50))
      assertStable()
      let label = count == 0 ? backupTitle
        : String(format: NSLocalizedString("selection_backup_count", comment: ""), count)
      XCTAssertTrue(matching(label) === backup)
    }
    await state.action.request(prepare: { false }, submit: { true }, failure: { nil })
    state.count = 0
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(matching(NSLocalizedString("selection_backup_added", comment: "")) === backup)
    assertStable()
  }

  func testGridToolbarIgnoresInactiveOwnerCleanupAndSupportsNoSelection() {
    let toolbar = MacGridToolbarState()
    let first = MacLibraryNavigation(), second = MacLibraryNavigation()
    let information = MacPhotoInfoStore()
    first.bindInformation(information); second.bindInformation(information)
    let firstOwner = UUID(), secondOwner = UUID()
    toolbar.update(owner: firstOwner, navigation: first, hasItems: true)
    toolbar.showInformation()
    XCTAssertTrue(information.isPresented)
    XCTAssertTrue(first.informationPresented)
    XCTAssertTrue(second.informationPresented)
    toolbar.update(owner: secondOwner, navigation: second, hasItems: true)
    toolbar.withdraw(owner: firstOwner)
    XCTAssertTrue(toolbar.canInspect)
    XCTAssertTrue(information.isPresented)
    toolbar.showInformation()
    XCTAssertFalse(information.isPresented)
    XCTAssertFalse(first.informationPresented)
    XCTAssertFalse(second.informationPresented)
    toolbar.withdraw(owner: secondOwner)
    XCTAssertFalse(toolbar.hasSource)
    XCTAssertFalse(toolbar.canInspect)
  }
}

@MainActor private final class SelectionToolbarFixtureState: ObservableObject {
  @Published var count = 0
  let action = SelectionBackupAction()
  let information = MacGridToolbarState()
}

private struct SelectionToolbarFixture: View {
  @ObservedObject var state: SelectionToolbarFixtureState
  var body: some View {
    NavigationSplitView { Text("Sidebar") } detail: {
      Text("Toolbar").frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Toolbar")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {} label: { Image(systemName: "line.3.horizontal.decrease") }
          MacGridInfoButton(state: state.information)
          MacSelectionBackupControl(action: state.action, count: state.count,
            identifier: "library.backup_selected", submit: {})
        }
      }
    }.frame(width: 1000, height: 600)
  }
}
