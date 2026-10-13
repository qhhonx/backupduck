import SwiftUI
import UIKit
import ObjectiveC

struct IOSSettingsPage: View {
  @ObservedObject var model: BackupModel
  @State private var logs = false
  @State private var editingName = false
  @AppStorage("duckAppearance") private var appearance = "system"
  @State private var retryingInitialization = false
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        IOSPrototypeHeader("nav_settings")
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if !model.ready {
              if let message = model.message {
                DuckNotice(title: LocalizedStringKey(message == NSLocalizedString("pairing_unlock_wait", comment: "")
                  ? NSLocalizedString("backup_initializing", comment: "") : message), tone: .attention)
                Button("retry_task") {
                  guard !retryingInitialization else { return }
                  retryingInitialization = true
                  Task { await model.open(); retryingInitialization = false }
                }.disabled(retryingInitialization).iosPrototypeAction()
              } else { ProgressView("backup_initializing") }
            }
            IOSPreferenceSection(title: "device_identity") {
              if let profile = model.deviceSnapshot?.device {
                Button { editingName = true } label: {
                  IOSPreferenceRow(title: "device_this_device", symbol: "iphone") {
                    IOSPreferenceValue(value: profile.name, indicator: nil)
                  }
                }.buttonStyle(.plain).accessibilityIdentifier("device.rename")
              } else {
                DuckNotice(title: model.deviceError == nil ? "backup_initializing" : "device_load_failed")
                if model.deviceError != nil { Button("retry_task") { Task { await model.refreshDeviceStatus() } } }
              }
            }
            IOSPreferenceSection(title: "apple_display_language") {
              IOSPreferenceRow(title: "apple_appearance") {
              Menu {
                Picker("apple_appearance", selection: $appearance) {
                  Text("apple_appearance_system").tag("system")
                  Text("apple_appearance_light").tag("light")
                  Text("apple_appearance_dark").tag("dark")
                }.pickerStyle(.inline)
              } label: {
                  IOSPreferenceValue(value: NSLocalizedString("apple_appearance_" + appearance, comment: ""), indicator: "chevron.down", actionable: true)
                    .frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("settings.appearance")
              }
              Divider()
              IOSPreferenceRow(title: "apple_language", symbol: "globe") {
                IOSPreferenceValue(value: Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "—", indicator: nil)
              }.accessibilityIdentifier("settings.language")
            }
            IOSPreferenceSection(title: "nav_library") {
              PreviewCloudSetting()
            }
            IOSPreferenceSection(title: "apple_local_storage") {
              NavigationLink {
                IOSPrototypeDestination(title: "settings_cache") {
                  IOSStoragePreferences(model: model, scope: .cache)
                }
              } label: {
                IOSPreferenceRow(title: "settings_cache", symbol: "internaldrive") {
                  if let snapshot = model.storage {
                    IOSPreferenceValue(value: "\(ByteCountFormatter.string(fromByteCount: Int64(snapshot.used_bytes), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.settings.cache_budget_bytes), countStyle: .file))")
                  }
                }
              }.buttonStyle(.plain).accessibilityIdentifier("settings.cache")
            }
            IOSPreferenceSection(title: "settings_diagnostics") {
              Button { logs = true } label: {
                IOSPreferenceRow(title: "activity_log", symbol: "list.bullet.rectangle") { IOSPreferenceValue(value: nil) }
              }.buttonStyle(.plain).accessibilityIdentifier("settings.activity_log")
              Divider()
              NavigationLink {
                IOSPrototypeDestination(title: "settings_log_retention") { IOSStoragePreferences(model: model, scope: .logs) }
              } label: {
                IOSPreferenceRow(title: "settings_log_retention", symbol: "clock.arrow.circlepath") { IOSPreferenceValue(value: nil) }
              }.buttonStyle(.plain).accessibilityIdentifier("settings.log_retention")
            }
            IOSPreferenceSection(title: "apple_help_about") {
              NavigationLink { IOSPrototypeDestination(title: "help_title") { BackupHelp() } } label: {
                IOSPreferenceRow(title: "help_title", symbol: "questionmark.circle") { IOSPreferenceValue(value: nil) }
              }.buttonStyle(.plain).accessibilityIdentifier("settings.help")
              Divider()
              NavigationLink { IOSAboutPage() } label: {
                IOSPreferenceRow(title: "about_title") {
                  IOSPreferenceValue(value: Bundle.main.object(forInfoDictionaryKey: "BackupDuckReleaseVersion") as? String ?? "—")
                }
              }.buttonStyle(.plain).accessibilityIdentifier("settings.about")
            }
          }.iosPrototypePageBody()
        }
      }.background(DuckColors.canvas).foregroundStyle(DuckColors.text).toolbar(.hidden, for: .navigationBar).symbolVariant(.none)
        .task { if model.deviceSnapshot == nil { await model.refreshDeviceStatus() } }
        .task(id: model.ready) { if model.ready { await model.refreshStorage() } }
    }.sheet(isPresented: $logs) { ActivityLogView() }
      .sheet(isPresented: $editingName) {
        if let name = model.deviceSnapshot?.device.name { DeviceNameEditor(model: model, name: name) }
      }
  }
}

private struct IOSAboutPage: View {
  var body: some View {
    IOSPrototypeDestination(title: "about_title") {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          IOSPreferenceSection(title: "settings_version") {
            IOSPreferenceRow(title: "about_app_version") {
              Text("\(Bundle.main.object(forInfoDictionaryKey: "BackupDuckReleaseVersion") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
          }
          IOSPreferenceGroup {
            Link(destination: URL(string: "https://backupduck.app")!) {
              IOSPreferenceRow(title: "official_website") {
                IOSPreferenceValue(value: nil)
              }
            }.buttonStyle(.plain).accessibilityIdentifier("about.website")
          }
        }.iosPrototypePageBody()
      }
    }
  }
}

struct IOSBackupPreferences: View {
  @ObservedObject var model: BackupModel
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .headline) private var headingSize = 19
  var body: some View {
    IOSPrototypeDestination(title: "backup_settings") {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          IOSPreferenceSection(title: "source_system_library") {
            IOSPreferenceRow(title: "auto_backup_new", note: "auto_backup_explanation", symbol: "photo.on.rectangle") {
              Toggle("auto_backup_new", isOn: Binding(get: { model.autoBackup }, set: { enabled in Task { await model.setAutoBackup(enabled) } }))
                .labelsHidden().disabled(!model.ready || model.pairing == nil || model.changingAutoBackup)
            }

            if let error = model.autoBackupError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).padding(16) }
            if model.discoveryPending > 0 { LabeledContent("discovery_pending", value: model.discoveryPending.formatted()).padding(16) }
            if model.historyUnavailable { DuckNotice(title: "error_history_unavailable", tone: .attention).padding(16) }
          }
          BackupScopeSettings()
          IOSPreferenceSection(title: "transfer_settings") {
            IOSPreferenceRow(title: "transfer_concurrency", note: "transfer_concurrency_note", controlColumnWidth: 120) {
            Menu {
              Picker("transfer_concurrency", selection: Binding(get: { model.concurrentUploads }, set: { value in Task { await model.setConcurrentUploads(value) } })) {
                ForEach(1...4, id: \.self) { Text($0.formatted()).tag($0) }
              }.pickerStyle(.inline)
            } label: {
                IOSStorageValue(value: model.concurrentUploads.formatted(), adjustable: true)
            }.buttonStyle(.plain).frame(minHeight: DuckPreferenceMetrics.rowHeight).disabled(!model.ready || model.savingConcurrency)
              .accessibilityIdentifier("settings.transfer_concurrency")
            }

            if let error = model.concurrencyError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).padding(16) }
          }
          IOSPreferenceSection(title: "history_title") {
            VStack(alignment: .leading, spacing: 16) {
              Text("history_explanation").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
              if let status = model.historicalImport {
                LabeledContent("history_scan_status", value: NSLocalizedString("history_state_" + status.state, comment: ""))
                Text(String(format: NSLocalizedString("history_counts", comment: ""), status.checked, status.pending)).font(.callout).foregroundStyle(DuckColors.textSecondary)
                Button { Task { await model.controlHistoricalImport(status.state == "scanning" ? "pause" : status.state == "paused" ? "resume" : status.state == "scanned" ? "restart" : "start") } } label: {
                  Text(status.state == "scanning" ? "history_pause" : status.state == "paused" ? "history_resume" : status.state == "scanned" ? "history_scan_again" : "history_start")
                }.iosPrototypeAction(primary: status.state != "scanning")
              } else {
                Button("history_start") { Task { await model.controlHistoricalImport("start") } }.iosPrototypeAction(primary: true)
              }

              if model.paused, model.historicalImport?.state == "scanning" {
                Text("history_backup_paused").foregroundStyle(DuckColors.textSecondary)
                Button("resume_backup") { Task { await model.setPaused(false); await model.scanHistoricalImport() } }.iosPrototypeAction()
              }
              if let error = model.historyError {
                DuckNotice(title: LocalizedStringKey(error), tone: .failure)
                Button(error == NSLocalizedString("error_history_snapshot_unavailable", comment: "") ? "history_scan_again" : "retry_task") {
                  Task {
                    if error == NSLocalizedString("error_history_snapshot_unavailable", comment: "") { await model.controlHistoricalImport("restart") }
                    else { await model.refreshHistoricalImport(); await model.scanHistoricalImport() }
                  }
                }.iosPrototypeAction()
              }
            }.padding(20).disabled(!model.ready || model.pairing == nil || model.changingHistory)
          }
          IOSPreferenceSection(title: "background_section") {
            IOSPreferenceRow(title: "keep_screen_awake_during_backup", note: "keep_screen_awake_explanation", symbol: "sun.max") {
              Toggle("keep_screen_awake_during_backup", isOn: $keepScreenAwake).labelsHidden()
            }
          }
          Text(NSLocalizedString("background_explanation", comment: "") + " " + NSLocalizedString("background_force_quit", comment: ""))
            .font(.footnote).foregroundStyle(DuckColors.textSecondary)
        }.iosPrototypePageBody()
      }
    }.task { await model.refreshHistoricalImport() }
  }
}

/// iOS page structure follows the authored prototype. NavigationStack continues
/// owning navigation/state; its default large/centered title is not the layout.
struct IOSPrototypeHeader<Trailing: View>: View {
  let title: LocalizedStringKey
  var back: (() -> Void)? = nil
  @ViewBuilder var trailing: () -> Trailing
  @ScaledMetric(relativeTo: .title2) private var titleSize = 24
  var body: some View {
    HStack(spacing: 12) {
      if let back {
        Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 22)).frame(width: 44, height: 44).contentShape(Rectangle()) }
          .buttonStyle(.plain).foregroundStyle(DuckColors.action)
          .accessibilityLabel(Text("apple_back")).accessibilityIdentifier("page.header.back")
      }
      Text(title).iosPrototypeText(size: titleSize, weight: .semibold, lineHeight: 1.2)
        .accessibilityIdentifier("page.header.title")
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      trailing()
    }.padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 60)
      .background(DuckColors.surface).overlay(alignment: .bottom) { Divider() }
  }
}
extension IOSPrototypeHeader where Trailing == EmptyView {
  init(_ title: LocalizedStringKey, back: (() -> Void)? = nil) {
    self.title = title; self.back = back; trailing = { EmptyView() }
  }
}
struct IOSPrototypeDestination<Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder var content: () -> Content
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(spacing: 0) { IOSPrototypeHeader(title, back: { dismiss() }); content() }
      .background(DuckColors.canvas).foregroundStyle(DuckColors.text).toolbar(.hidden, for: .navigationBar).symbolVariant(.none)
      .background(IOSNativeEdgeBack().frame(width: 0, height: 0).allowsHitTesting(false))
  }
}

/// SwiftUI's hidden navigation bar suppresses UIKit's default edge-pop delegate.
/// Keep the existing recognizer/targets (and native interactive transition), but
/// replace that bar-visibility gate with stack/transition safety checks. This is
/// scoped to the actual NavigationStack's UINavigationController, not a global
/// UIKit extension or a custom full-screen drag/pop implementation.
private struct IOSNativeEdgeBack: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> EdgeBackController { EdgeBackController() }
  func updateUIViewController(_ controller: EdgeBackController, context: Context) {
    controller.installWhenAttached()
  }

  final class EdgeBackController: UIViewController {
    override func loadView() {
      view = UIView()
      view.backgroundColor = .clear
      view.isUserInteractionEnabled = false
    }
    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      installWhenAttached()
    }
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      installWhenAttached()
    }
    func installWhenAttached() {
      guard let navigationController,
        let gesture = navigationController.interactivePopGestureRecognizer else { return }
      let delegate: NativePopDelegate
      if let existing = objc_getAssociatedObject(navigationController, &NativePopDelegate.associatedKey) as? NativePopDelegate {
        delegate = existing
      } else {
        delegate = NativePopDelegate(navigation: navigationController, original: gesture.delegate)
        objc_setAssociatedObject(navigationController, &NativePopDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      }
      gesture.delegate = delegate
      gesture.isEnabled = true
    }
  }
}

@MainActor private final class NativePopDelegate: NSObject, UIGestureRecognizerDelegate {
  static var associatedKey: UInt8 = 0
  private weak var navigation: UINavigationController?
  private weak var original: (any UIGestureRecognizerDelegate)?
  init(navigation: UINavigationController, original: (any UIGestureRecognizerDelegate)?) {
    self.navigation = navigation
    self.original = original
  }
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let navigation,
      gestureRecognizer === navigation.interactivePopGestureRecognizer,
      navigation.viewControllers.count > 1,
      navigation.topViewController?.view.window != nil,
      navigation.presentedViewController == nil,
      navigation.transitionCoordinator == nil else { return false }
    return true
  }
  // Preserve UIKit's other gesture relationships, including scroll views and
  // touch/press/event filtering. Only the hidden-bar shouldBegin gate changes.
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    original?.gestureRecognizer?(gestureRecognizer, shouldRecognizeSimultaneouslyWith: other) ?? false
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
    original?.gestureRecognizer?(gestureRecognizer, shouldRequireFailureOf: other) ?? false
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    original?.gestureRecognizer?(gestureRecognizer, shouldBeRequiredToFailBy: other) ?? false
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    original?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
    original?.gestureRecognizer?(gestureRecognizer, shouldReceive: press) ?? true
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
    original?.gestureRecognizer?(gestureRecognizer, shouldReceive: event) ?? true
  }
}
struct IOSPreferenceSection<Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder var content: () -> Content
  @ScaledMetric(relativeTo: .headline) private var titleSize = 19
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).iosPrototypeText(size: titleSize, weight: .semibold, lineHeight: 1.4)
      VStack(spacing: 0, content: content)
        .background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(DuckColors.border, lineWidth: 1) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct IOSPreferenceGroup<Content: View>: View {
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(spacing: 0, content: content).background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(DuckColors.border, lineWidth: 1))
  }
}
struct IOSPreferenceRow<Control: View>: View {
  let title: LocalizedStringKey
  var note: LocalizedStringKey? = nil
  var symbol: String? = nil
  var controlColumnWidth: CGFloat? = nil
  @ViewBuilder var control: () -> Control
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var noteSize = 13
  @Environment(\.dynamicTypeSize) private var textSize
  var body: some View {
    Group {
      if textSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          label
          control().foregroundStyle(DuckColors.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        HStack(alignment: .center, spacing: 12) {
          label
          control().foregroundStyle(DuckColors.textSecondary).frame(width: controlColumnWidth, alignment: .trailing)
        }
      }
    }.padding(.horizontal, 16).padding(.vertical, note == nil ? 0 : 16)
      .frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle())
  }
  private var label: some View {
    HStack(alignment: textSize.isAccessibilitySize ? .top : .center, spacing: 12) {

      VStack(alignment: .leading, spacing: 5) {
        Text(title).iosPrototypeText(size: bodySize, weight: .semibold)
        if let note { Text(note).iosPrototypeText(size: noteSize, lineHeight: 1.6)
          .foregroundStyle(DuckColors.textSecondary).fixedSize(horizontal: false, vertical: true) }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
extension View {
  func iosPrototypeAction(primary: Bool = false) -> some View {
    self.buttonStyle(IOSPrototypeActionStyle(primary: primary))
  }
}
private struct IOSPrototypeActionStyle: ButtonStyle {
  let primary: Bool
  @Environment(\.isEnabled) private var enabled
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: bodySize, weight: primary ? .semibold : .regular))
      .foregroundStyle(primary ? DuckColors.surface : DuckColors.action)
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: DuckPreferenceMetrics.rowHeight)
      .background(primary ? DuckColors.action : DuckColors.surface, in: RoundedRectangle(cornerRadius: 10))
      .overlay { RoundedRectangle(cornerRadius: 10).stroke(primary ? DuckColors.action : DuckColors.border, lineWidth: 1) }
      .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
  }
}

/// CSS line-height is part of the frozen density contract. UIKit's glyph box is
/// smaller, so add half-leading outside plus inter-line leading, without fixing
/// a height or clipping multilingual/accessible text. Callers supply scaled size.
extension View {
  func iosPrototypeText(size: CGFloat, weight: Font.Weight = .regular, lineHeight: CGFloat = 1.5) -> some View {
    let extra = max(0, size * lineHeight - UIFont.systemFont(ofSize: size).lineHeight)
    return font(.system(size: size, weight: weight)).lineSpacing(extra).padding(.vertical, extra / 2)
  }
}

/// Presentation-only adapter: every write uses the shared StorageModel methods
/// and keeps its scoped sticky failures; no second persistence implementation.
private struct IOSStoragePreferences: View {
  @ObservedObject var model: BackupModel
  let scope: StoragePreferenceScope
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let snapshot = model.storage {
          if scope == .cache {
            IOSPreferenceSection(title: "ios_cache_preparation_group") {
              IOSPreferenceRow(title: "storage_cache_used", symbol: "internaldrive", controlColumnWidth: 120) { IOSStorageValue(value: bytes(snapshot.used_bytes), adjustable: false) }
              Divider()
              IOSPreferenceRow(title: "storage_cache_budget", controlColumnWidth: 120) {
              Menu {
                Picker("storage_cache_budget", selection: Binding(get: { Int(snapshot.settings.cache_budget_bytes >> 30) }, set: { value in
                  var next = snapshot.settings; next.cache_budget_bytes = UInt64(value) << 30
                  Task { await model.saveStorage(next) }
                })) { ForEach([1, 2, 5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag($0) } }.pickerStyle(.inline)
              } label: {
                  IOSStorageValue(value: "\(snapshot.settings.cache_budget_bytes >> 30) GB", adjustable: true)
              }.buttonStyle(.plain).frame(minHeight: DuckPreferenceMetrics.rowHeight).accessibilityIdentifier("settings.cache_budget")
              }

            }.disabled(model.savingStorage)
            Text("ios_cache_budget_note").font(.footnote).foregroundStyle(DuckColors.textSecondary)
            IOSPreferenceSection(title: "ios_cache_reserve_group") {
              IOSPreferenceRow(title: "storage_disk_free", symbol: "internaldrive", controlColumnWidth: 120) { IOSStorageValue(value: bytes(snapshot.free_bytes), adjustable: false) }
              Divider()
              IOSPreferenceRow(title: "storage_min_free", controlColumnWidth: 120) {
              Menu {
                Picker("storage_min_free", selection: Binding(get: { Int(snapshot.settings.min_free_bytes >> 30) }, set: { value in
                  var next = snapshot.settings; next.min_free_bytes = UInt64(value) << 30
                  Task { await model.saveStorage(next) }
                })) { ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) GB").tag($0) } }.pickerStyle(.inline)
              } label: {
                  IOSStorageValue(value: "\(snapshot.settings.min_free_bytes >> 30) GB", adjustable: true)
              }.buttonStyle(.plain).frame(minHeight: DuckPreferenceMetrics.rowHeight).accessibilityIdentifier("settings.min_free")
              }

            }.disabled(model.savingStorage)
            Text("ios_cache_reserve_note").font(.footnote).foregroundStyle(DuckColors.textSecondary)
            IOSPreferenceSection(title: "ios_cache_reclaim_group") {
              IOSPreferenceRow(title: "storage_auto_reclaim", symbol: "arrow.triangle.2.circlepath") {
                Toggle("storage_auto_reclaim", isOn: Binding(get: { snapshot.settings.auto_reclaim }, set: { value in
                  var next = snapshot.settings; next.auto_reclaim = value
                  Task { await model.saveStorage(next) }
                })).labelsHidden().disabled(model.savingStorage)
              }
              Divider()
              NavigationLink {
                IOSPrototypeDestination(title: "storage_reclaim_now") { IOSCacheReclaim(model: model) }
              } label: {
                IOSPreferenceRow(title: "storage_reclaim_now", symbol: "arrow.clockwise") { IOSPreferenceValue(value: nil) }
              }.buttonStyle(.plain).accessibilityIdentifier("settings.reclaim_cache")
            }
            Text("ios_cache_reclaim_safety").font(.footnote).foregroundStyle(DuckColors.textSecondary)
            if let reason = snapshot.reason, ["local_free_space", "local_cache_budget"].contains(reason) {
              DuckNotice(title: LocalizedStringKey("error_" + reason), tone: .attention)
                .accessibilityIdentifier("settings.cache_limit_reason")
            }
          } else {
            IOSPreferenceSection(title: "logs_retention") {
              ForEach([1, 7, 14, 30, 90], id: \.self) { value in
                Button {
                  var next = snapshot.settings; next.log_days = value
                  Task { await model.saveStorage(next) }
                } label: {
                  HStack {

                    Text(String(format: NSLocalizedString("logs_days", comment: ""), value))
                    Spacer()
                    if snapshot.settings.log_days == value { Image(systemName: "checkmark").foregroundStyle(DuckColors.action) }
                  }.frame(maxWidth: .infinity, minHeight: DuckPreferenceMetrics.rowHeight, alignment: .leading).padding(.horizontal, 16).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("settings.log_days.\(value)")
                  .accessibilityAddTraits(snapshot.settings.log_days == value ? .isSelected : [])
                if value != 90 { Divider() }
              }
            }.disabled(model.savingStorage)
            IOSPreferenceSection(title: "logs_limit") {
              ForEach([1000, 5000, 10000, 20000], id: \.self) { value in
                Button {
                  var next = snapshot.settings; next.log_limit = value
                  Task { await model.saveStorage(next) }
                } label: {
                  HStack {

                    Text(value.formatted()); Spacer()
                    if snapshot.settings.log_limit == value { Image(systemName: "checkmark").foregroundStyle(DuckColors.action) }
                  }.frame(maxWidth: .infinity, minHeight: DuckPreferenceMetrics.rowHeight, alignment: .leading).padding(.horizontal, 16).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("settings.log_limit.\(value)")
                  .accessibilityAddTraits(snapshot.settings.log_limit == value ? .isSelected : [])
                if value != 20000 { Divider() }
              }
            }.disabled(model.savingStorage)
          }

          if let error = model.storageSettingsError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).accessibilityIdentifier("settings.storage_save_error") }
          if let error = model.storageError { DuckNotice(title: LocalizedStringKey(error), tone: .failure) }
        } else if let error = model.storageError {
          DuckNotice(title: LocalizedStringKey(error), tone: .failure)
          Button("retry_task") { Task { await model.refreshStorage() } }.iosPrototypeAction()
        } else { ProgressView(model.ready ? "storage_loading" : "backup_initializing") }
      }.iosPrototypePageBody()
    }.task { await model.refreshStorage() }
  }
  private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) }
}

/// Static/read-write values use identical glyph geometry. Only this trailing
/// value anchors the native menu; the row's title and explanation stay visible.
struct IOSPreferenceValue: View {
  let value: String?
  var indicator: String? = "chevron.right"
  var actionable = false
  @ScaledMetric(relativeTo: .body) private var size = 16
  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      if let value {
        Text(value).font(.system(size: size)).monospacedDigit()
          .fixedSize(horizontal: false, vertical: true)
          .foregroundStyle(actionable ? DuckColors.action : DuckColors.textSecondary)
      }
      Image(systemName: indicator ?? "chevron.right").font(.system(size: 11))
        .frame(width: 16, height: 22).foregroundStyle(DuckColors.action)
        .opacity(indicator == nil ? 0 : 1).accessibilityHidden(true)
    }.frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle())
  }
}
private struct IOSStorageValue: View {
  let value: String
  let adjustable: Bool
  var body: some View {
    IOSPreferenceValue(value: value, indicator: adjustable ? "chevron.up.chevron.down" : nil,
      actionable: adjustable).frame(width: 120, alignment: .trailing)
  }
}

private struct IOSCacheReclaim: View {
  @ObservedObject var model: BackupModel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        DuckNotice(title: "storage_reclaim_check_help")
        if model.reclaimingCache { ProgressView("storage_reclaim_running") }
        if let snapshot = model.storage, snapshot.used_bytes == 0,
          !model.reclaimingCache, model.storageError == nil,
          model.cacheReclaimResult == nil, model.cacheReclaimError == nil {
          Text("storage_cache_empty").font(.footnote).foregroundStyle(DuckColors.textSecondary)
            .accessibilityIdentifier("settings.reclaim_empty")
        }
        if let error = model.storageError { DuckNotice(title: LocalizedStringKey(error), tone: .failure) }
        if let result = model.cacheReclaimResult { DuckNotice(title: LocalizedStringKey(result)).accessibilityIdentifier("settings.reclaim_result") }
        if let error = model.cacheReclaimError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).accessibilityIdentifier("settings.cache_reclaim_error") }
        Button { Task { await model.reclaimCache(reportResult: true) } } label: {
          Text(LocalizedStringKey(model.reclaimingCache ? "storage_reclaim_running" : "storage_reclaim_now")).frame(maxWidth: .infinity)
        }.iosPrototypeAction(primary: true).disabled(model.reclaimingCache || !model.ready || model.storage == nil || model.storage?.used_bytes == 0)
          .accessibilityIdentifier("settings.reclaim_confirm")
      }.iosPrototypePageBody()
    }.task { await model.refreshStorage() }
  }
}

extension View {
  /// The authored iPad content column stays 640 points including page insets.
  func iosPrototypePageBody() -> some View {
    frame(maxWidth: 600, alignment: .leading).padding(20).frame(maxWidth: .infinity)
  }
}

struct IOSCheckboxToggleStyle: ToggleStyle {
  @ScaledMetric(relativeTo: .body) private var symbolSize = 16
  func makeBody(configuration: Configuration) -> some View {
    Button { configuration.isOn.toggle() } label: {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Image(systemName: configuration.isOn ? "checkmark.square" : "square")
          .symbolVariant(.none).font(.system(size: symbolSize, weight: .regular))
          .foregroundStyle(configuration.isOn ? DuckColors.action : DuckColors.textSecondary)
          .frame(width: symbolSize).accessibilityHidden(true)
        configuration.label.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.buttonStyle(.plain).frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle()).accessibilityAddTraits(configuration.isOn ? .isSelected : [])
  }
}

extension View {
  /// iPad keeps a centered native form host. Modern SwiftUI allows fitting the
  /// horizontal size to the authored 540-point ideal; iOS 17 uses system form.
  @ViewBuilder func iosPrototypeSheetHost() -> some View {
    if UIDevice.current.userInterfaceIdiom == .pad {
      if #available(iOS 18.0, *) {
        self.frame(idealWidth: 540).presentationSizing(.form.fitted(horizontal: true, vertical: false))
      } else { self }
    } else { self }
  }
}
