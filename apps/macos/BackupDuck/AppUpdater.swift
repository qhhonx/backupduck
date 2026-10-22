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
  @Published private(set) var status: MacUpdateStatus = .notChecked
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
      controller.updater.observe(\.sessionInProgress, options: [.new]) { [weak self] value, _ in
        let inProgress = value.sessionInProgress
        Task { @MainActor in
          if inProgress { self?.status = .checking }
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
    status = .checking
    controller.checkForUpdates(nil)
  }
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { status = .available }
  func updaterDidNotFindUpdate(_ updater: SPUUpdater) { status = .upToDate }
  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    if status == .checking { status = error == nil ? .notChecked : .failed }
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
      check: updater.check)
  }
}

#endif

/// Status comes from Sparkle observations, never from the installed version alone.
enum MacUpdateStatus {
  case notChecked, checking, upToDate, available, failed
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
  var body: some View {
    Section {
      NavigationLink {
        Form {
          Section {
            Text(status.title).foregroundStyle(.primary)
              .accessibilityIdentifier("settings.updates.status")
            Button("updates_check", action: check).buttonStyle(.bordered).disabled(!canCheck)
              .accessibilityIdentifier("settings.updates.check")
            Toggle("updates_automatic", isOn: automaticChecks)
              .toggleStyle(DuckPreferenceToggleStyle())
              .accessibilityIdentifier("settings.updates.automatic")
          }
        }
        .formStyle(.grouped)
        .navigationTitle("updates_title")
      } label: {
        DuckAboutVersionLabel(status: status.title)
      }.accessibilityIdentifier("about.version")
    }
  }
}
