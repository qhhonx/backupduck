import AppKit
import Combine
import SwiftUI
#if BACKUPDUCK_APP_STORE
@MainActor final class AppUpdater: ObservableObject {
  static let shared = AppUpdater()
  func start() async {}
}

struct UpdateSettings: View {
  var body: some View { Section { DuckAboutVersionLabel() } }
}

#else
import Sparkle

@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
  static let shared = AppUpdater()
  @Published private(set) var canCheck = false
  @Published private(set) var automaticChecks = true
  /// The last check's result. Checking is shown only while Sparkle's session or
  /// a requested check is running, so a missed callback cannot leave it checking.
  @Published private var result: MacUpdateStatus = .notChecked
  @Published private var inSession = false
  @Published private var requested = false
  var status: MacUpdateStatus { inSession || requested ? .checking : result }
  private var controller: SPUStandardUpdaterController!
  private var observations: [NSKeyValueObservation] = []
  private var started = false
  private let resumeKey = "resumeAfterAppUpdate"

  override init() {
    super.init()
    controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    observations = [
      controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] value, _ in
        Task { @MainActor in self?.canCheck = value.canCheckForUpdates }
      },
      controller.updater.observe(\.sessionInProgress, options: [.initial, .new]) { [weak self] value, _ in
        let inProgress = value.sessionInProgress
        Task { @MainActor in
          self?.inSession = inProgress
          if !inProgress { self?.requested = false }
        }
      },
      controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] value, _ in
        Task { @MainActor in self?.automaticChecks = value.automaticallyChecksForUpdates }
      }
    ]
  }
  func start() async {
    guard !started else { return }
    started = true
    if UserDefaults.standard.bool(forKey: resumeKey), BackupModel.shared.ready {
      await BackupModel.shared.setPaused(false)
      if !BackupModel.shared.paused { UserDefaults.standard.removeObject(forKey: resumeKey) }
    }
    controller.startUpdater()
  }
  func check() {
    guard canCheck else { return }
    requested = true
    controller.checkForUpdates(nil)
  }
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { result = .available }
  func updaterDidNotFindUpdate(_ updater: SPUUpdater) { result = .upToDate }
  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    // No update is reported as an error too; only a real failure replaces the result.
    if let error = error as NSError?, error.domain == SUSparkleErrorDomain,
      error.code != Int(SUError.noUpdateError.rawValue), result != .available { result = .failed }
    requested = false
  }
  func setAutomaticChecks(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
  func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
    Task { @MainActor in
      let model = BackupModel.shared
      let resume = model.ready && !model.paused
      if model.ready { await model.setPaused(true) }
      // Do not replace the process while PhotoKit is writing an original.
      while model.importing || model.scanningHistory {
        try? await Task.sleep(nanoseconds: 200_000_000)
      }
      UserDefaults.standard.set(resume, forKey: resumeKey)
      installHandler()
    }
    return true
  }
}

struct UpdateSettings: View {
  @ObservedObject private var updater = AppUpdater.shared
  var body: some View {
    MacUpdateSection(status: updater.status, canCheck: updater.canCheck,
      automaticChecks: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks),
      check: updater.check, liveDetail: AnyView(MacAppUpdaterDetail()))
  }
}

/// The update page observes the updater itself: a page opened in the Settings
/// pane keeps its content, so values captured when it opened would go stale.
private struct MacAppUpdaterDetail: View {
  @ObservedObject private var updater = AppUpdater.shared
  var body: some View {
    MacUpdateDetail(status: updater.status, canCheck: updater.canCheck,
      automaticChecks: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks), check: updater.check)
  }
}

#endif

/// Status comes from Sparkle observations, never from the installed version alone.
enum MacUpdateStatus {
  case notChecked, checking, upToDate, available, failed
  func title(automatic: Bool) -> LocalizedStringKey {
    if self == .notChecked && automatic { return "updates_background" }
    return title
  }
  var title: LocalizedStringKey {
    switch self {
    case .notChecked: "updates_not_checked"
    case .checking: "updates_checking"
    case .upToDate: "updates_up_to_date"
    case .available: "updates_available"
    case .failed: "updates_check_failed"
    }
  }
}

/// About owns the version; its destination owns only update status and controls.
struct MacUpdateSection: View {
  var status: MacUpdateStatus = .notChecked
  var canCheck = true
  var automaticChecks: Binding<Bool> = .constant(true)
  var check: () -> Void = {}
  var liveDetail: AnyView? = nil
  var body: some View {
    Section {
      DuckSettingsLink(title: Text("updates_title")) {
        if let liveDetail { liveDetail }
        else { MacUpdateDetail(status: status, canCheck: canCheck, automaticChecks: automaticChecks, check: check) }
      } label: {
        DuckAboutVersionLabel(status: status.title(automatic: automaticChecks.wrappedValue))
      }.accessibilityIdentifier("about.version")
    }
  }
}

/// Status with its action on one row, then the automatic switch.
struct MacUpdateDetail: View {
  var status: MacUpdateStatus
  var canCheck: Bool
  var automaticChecks: Binding<Bool>
  var check: () -> Void
  var body: some View {
    Form {
      Section {
        LabeledContent {
          Button("updates_check_button", action: check).disabled(!canCheck || status == .checking)
            .accessibilityIdentifier("settings.updates.check")
        } label: {
          Text(status.title(automatic: automaticChecks.wrappedValue)).foregroundStyle(.primary).accessibilityIdentifier("settings.updates.status")
        }
        Toggle("updates_automatic", isOn: automaticChecks)
          .toggleStyle(DuckPreferenceToggleStyle())
          .accessibilityIdentifier("settings.updates.automatic")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("updates_title")
  }
}
