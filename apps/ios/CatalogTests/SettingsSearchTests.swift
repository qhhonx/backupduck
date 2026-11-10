import XCTest
import SwiftUI
import UIKit
@testable import BackupDuckCatalog

/// Production supporting pages inside native tab and pushed navigation containers.
/// The catalog supplies synthetic albums and never requests library access.
@MainActor final class SettingsSearchTests: XCTestCase {
  func testCancelKeepsViewportWithinSettledBounds() async throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
      for page in [SearchPage.albumsEmpty, .albums, .help] {
        try await exercise(page, style: style)
      }
    }
  }

  func testCancelAfterNativeLibraryContainmentKeepsViewportWithinSettledBounds() async throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
      for page in [SearchPage.albumsEmpty, .help] {
        try await exercise(page, style: style, visitLibrary: true)
      }
    }
  }

  private func exercise(_ page: SearchPage, style: UIUserInterfaceStyle, visitLibrary: Bool = false) async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let state = SearchNavigationState()
    state.tab = visitLibrary ? IOSAppTab.library.rawValue : IOSAppTab.settings.rawValue
    let fixture = ScopeCatalogFixture(id: page == .albumsEmpty ? "settings.scope.empty" : "settings.scope.albums")
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    window.overrideUserInterfaceStyle = style
    window.rootViewController = UIHostingController(rootView: SearchNavigationFixture(state: state, fixture: fixture))
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(500))
    if visitLibrary {
      state.tab = IOSAppTab.settings.rawValue
      try await Task.sleep(for: .milliseconds(500))
    }
    withAnimation { state.path = [page] }
    try await Task.sleep(for: .seconds(1))
    let navigation = try XCTUnwrap(findNavigation(window.rootViewController))
    let search = try XCTUnwrap(navigation.topViewController?.navigationItem.searchController)
    let content = descendants(try XCTUnwrap(navigation.topViewController?.view))
      .compactMap { $0 as? UIScrollView }.filter { $0.bounds.width >= window.bounds.width - 1 }
      .max { $0.bounds.height < $1.bounds.height }
    let viewport = try XCTUnwrap(content)
    let originalRule = fixture.store.rule
    XCTAssertFalse(search.isActive)
    for cycle in 0..<2 {
      search.searchBar.becomeFirstResponder()
      try await Task.sleep(for: .seconds(1))
      XCTAssertTrue(search.isActive)
      XCTAssertEqual(search.searchBar.text ?? "", "", "Cancellation restores an empty search")
      if cycle == 1 {
        // Text entry reaches the production binding; cancellation still uses the real button.
        search.searchBar.searchTextField.insertText("Family")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(search.searchBar.text, "Family")
      }
      let sampling = SearchViewportSamples(content: viewport, window: window)
      sampling.start()
      defer { sampling.stop() }
      let searchFrame = search.searchBar.convert(search.searchBar.bounds, to: window)
      let textFrame = search.searchBar.searchTextField.convert(search.searchBar.searchTextField.bounds, to: window)
      let controls = descendants(window).compactMap { $0 as? UIButton }.filter {
        let frame = $0.convert($0.bounds, to: window)
        return !$0.isHidden && $0.alpha > 0 && $0.isEnabled && !$0.allTargets.isEmpty &&
          frame.intersects(searchFrame) && !frame.intersects(textFrame)
      }
      XCTAssertEqual(controls.count, 1, "Use the native search cancellation button, excluding the text clear button")
      try XCTUnwrap(controls.first).sendActions(for: .touchUpInside)
      try await Task.sleep(for: .seconds(1))
      sampling.stop()
      XCTAssertFalse(search.isActive)
      XCTAssertEqual(search.searchBar.text ?? "", "")
      XCTAssertEqual(fixture.store.rule, originalRule, "Search and cancellation preserve album choices")
      let origins = sampling.origins
      XCTAssertGreaterThan(origins.count, 15, "Observe the entire transition, not only its endpoints")
      let start = try XCTUnwrap(origins.first), end = try XCTUnwrap(origins.last)
      XCTAssertEqual(start, end, accuracy: 2, "Cancellation restores the settled content origin")
      XCTAssertGreaterThanOrEqual(try XCTUnwrap(origins.min()), min(start, end) - 2,
        "Search cancellation must not move the content beyond its settled viewport")
      XCTAssertLessThanOrEqual(try XCTUnwrap(origins.max()), max(start, end) + 2,
        "Search cancellation must not move the content beyond its settled viewport")
    }
  }

  private func findNavigation(_ controller: UIViewController?) -> UINavigationController? {
    guard let controller else { return nil }
    if let navigation = controller as? UINavigationController,
       navigation.topViewController?.navigationItem.searchController != nil { return navigation }
    for child in controller.children {
      if let result = findNavigation(child) { return result }
    }
    return nil
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }
}

private enum SearchPage: String, Hashable { case albumsEmpty, albums, help }

@MainActor private final class SearchNavigationState: ObservableObject {
  @Published var path: [SearchPage] = []
  @Published var tab = IOSAppTab.settings.rawValue
}

private struct SearchNavigationFixture: View {
  @ObservedObject var state: SearchNavigationState
  let fixture: ScopeCatalogFixture
  var body: some View {
    IOSNativeTabs(selection: $state.tab) { tab in
      switch tab {
      case .library: AnyView(SearchLibraryFixture())
      case .backup: AnyView(Text("nav_backup"))
      case .settings: AnyView(IOSNativeNavigation(title: NSLocalizedString("settings_auto_backup", comment: ""),
        route: state.path.last?.rawValue, routeChanged: { if $0 == nil { state.path = [] } }, destination: { value in
          let page = SearchPage(rawValue: value)
          let content: AnyView = page == .help ? AnyView(HelpCenter())
            : AnyView(BackupScopeEditor(destination: .albums, store: fixture.store, model: fixture.albums))
          return UIHostingController(rootView: content)
        }) { Form { Text("settings_auto_backup") } })
      }
    }.background(DuckRole.background.ignoresSafeArea()).tint(DuckRole.accent)
  }
}

private struct SearchLibraryFixture: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> UINavigationController {
    CalendarNavigationController(rootViewController: CalendarGridController())
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

/// Test-only display-link observation catches excursions between settled endpoints.
/// It never drives animation or ships in the application.
@MainActor private final class SearchViewportSamples: NSObject {
  let content: UIScrollView
  let window: UIWindow
  private(set) var origins: [CGFloat] = []
  private var displayLink: CADisplayLink?
  init(content: UIScrollView, window: UIWindow) { self.content = content; self.window = window }
  func start() {
    sample()
    let link = CADisplayLink(target: self, selector: #selector(sample))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }
  func stop() {
    guard let displayLink else { return }
    sample()
    displayLink.invalidate()
    self.displayLink = nil
  }
  @objc private func sample() {
    guard let layer = content.layer.presentation(), let root = window.layer.presentation() else { return }
    origins.append(layer.convert(CGPoint.zero, to: root).y)
  }
}
