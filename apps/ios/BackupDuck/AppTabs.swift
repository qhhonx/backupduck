import SwiftUI
import UIKit

/// The iPhone app's root tabs. The app and the design catalog share these
/// labels so a catalog page sits in the same tab chrome as in production.
enum IOSAppTab: Int, CaseIterable, Identifiable {
  case library = 0, backup = 1, settings = 3
  var id: Int { rawValue }
  var title: LocalizedStringKey {
    switch self {
    case .library: "nav_photos"
    case .backup: "nav_backup"
    case .settings: "nav_settings"
    }
  }
  var symbol: String {
    switch self {
    case .library: "photo.on.rectangle.angled"
    case .backup: "arrow.triangle.2.circlepath"
    case .settings: "gearshape"
    }
  }
  var label: some View { Label(title, systemImage: symbol) }

}

extension View {
  @ViewBuilder func duckLibraryTabMinimization(selected: Bool) -> some View {
    if #available(iOS 26.0, *) { self.tabBarMinimizeBehavior(selected ? .onScrollUp : .never) }
    else { self }
  }
  @ViewBuilder func duckTabSurface() -> some View {
    if #available(iOS 26.0, *) { self }
    else {
      self.toolbarBackground(DuckRole.elevatedSurface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
  }
  @ViewBuilder func duckLibraryViewport() -> some View {
    if #available(iOS 26.0, *) { self.ignoresSafeArea(.container, edges: .bottom) }
    else { self }
  }
}

/// UIKit owns both tab containment and each media/navigation stack. Supporting
/// hosting controllers retain their own navigation preferences inside this owner.
struct IOSNativeTabs: View {
  @Binding var selection: Int
  let content: (IOSAppTab) -> AnyView
  var body: some View {
    IOSNativeTabContainer(selection: $selection, content: content).ignoresSafeArea(.container)
  }
}

private struct IOSNativeTabContainer: UIViewControllerRepresentable {
  @Binding var selection: Int
  let content: (IOSAppTab) -> AnyView
  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
  func makeUIViewController(context: Context) -> UITabBarController {
    let tabs = IOSNativeTabController()
    let pages = IOSAppTab.allCases.map { item in
      let host = UIHostingController(rootView: AnyView(content(item).ignoresSafeArea(.container).iosSupportingEnvironment(context.environment)))
      host.tabBarItem = UITabBarItem(title: NSLocalizedString(item.titleKey, comment: ""),
        image: UIImage(systemName: item.symbol), tag: item.rawValue)
      return host
    }
    context.coordinator.pages = pages
    tabs.viewControllers = pages
    tabs.delegate = context.coordinator
    tabs.tabBar.tintColor = DuckRole.accentUIColor
    updateUIViewController(tabs, context: context)
    return tabs
  }
  func updateUIViewController(_ tabs: UITabBarController, context: Context) {
    context.coordinator.selection = $selection
    for (item, page) in zip(IOSAppTab.allCases, context.coordinator.pages) {
      page.rootView = AnyView(content(item).ignoresSafeArea(.container).iosSupportingEnvironment(context.environment))
      page.tabBarItem.title = String(localized: String.LocalizationValue(item.titleKey), locale: context.environment.locale)
    }
    if let index = IOSAppTab.allCases.firstIndex(where: { $0.rawValue == selection }), tabs.selectedIndex != index {
      tabs.selectedIndex = index
    }
    if #available(iOS 26.0, *), selection != IOSAppTab.library.rawValue { tabs.tabBarMinimizeBehavior = .never }
  }
  final class Coordinator: NSObject, UITabBarControllerDelegate {
    var selection: Binding<Int>
    var pages: [UIHostingController<AnyView>] = []
    init(selection: Binding<Int>) { self.selection = selection }
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
      selection.wrappedValue = viewController.tabBarItem.tag
    }
  }
}

private extension IOSAppTab {
  var titleKey: String {
    switch self {
    case .library: "nav_photos"
    case .backup: "nav_backup"
    case .settings: "nav_settings"
    }
  }
}

private final class IOSNativeTabController: UITabBarController {
  override var childForStatusBarStyle: UIViewController? { selectedViewController }
  override var childForStatusBarHidden: UIViewController? { selectedViewController }
  override var childForHomeIndicatorAutoHidden: UIViewController? { selectedViewController }
}

// Hosting boundaries pass application values explicitly. Container-specific
// SwiftUI navigation preferences stay with the hosting page that created them.
// Dynamic Type follows the hosting controller's live UIKit traits.
extension View {
  func iosSupportingEnvironment(_ values: EnvironmentValues) -> some View {
    environment(\.locale, values.locale)
      .environment(\.duckReservedSettingsContent, values.duckReservedSettingsContent)
      .environment(\.duckFeedbackPreview, values.duckFeedbackPreview)
      .environment(\.duckStepMarkReducedTransparency, values.duckStepMarkReducedTransparency)
      .environment(\.duckFirstPhotoReducedMotion, values.duckFirstPhotoReducedMotion)
  }
}

struct IOSSupportingValues: Equatable {
  let locale: Locale
  let author: String?, email: String?, storeID: String?
  let feedbackPreview: Bool, reducedTransparency: Bool, reducedMotion: Bool
  init(_ values: EnvironmentValues) {
    locale = values.locale
    author = values.duckReservedSettingsContent.authorText
    email = values.duckReservedSettingsContent.feedbackEmail
    storeID = values.duckReservedSettingsContent.appStoreAppID
    feedbackPreview = values.duckFeedbackPreview
    reducedTransparency = values.duckStepMarkReducedTransparency
    reducedMotion = values.duckFirstPhotoReducedMotion
  }
}
