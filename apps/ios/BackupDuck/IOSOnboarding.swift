import Photos
import SwiftUI
import UIKit
import UserNotifications

/// Durable presentation intent only. The core remains the owner of backup work.
@MainActor final class IOSFirstRunProgress: ObservableObject {
  struct Record: Codable {
    var step = "welcome"
    var autoBackup = true
    var earlierPhotos: Bool?
    var photoAccess: String?
    var firstPhotoStarted: Date?
    var receiver: String?
    var scopeRegistered: Bool?
    var completed = false
    var notificationHandled = false
  }
  @Published private(set) var record: Record?
  private let defaults: UserDefaults
  private let key: String
  @Published private(set) var applyingScope = false
  @Published private(set) var scopeError: String?

  init(defaults: UserDefaults = .standard, key: String = "firstRunProgress.v1") {
    self.defaults = defaults; self.key = key
    record = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
  }
  func update(_ change: (inout Record) -> Void) {
    var next = record ?? Record()
    change(&next)
    guard let data = try? JSONEncoder().encode(next) else { return }
    defaults.set(data, forKey: key)
    record = next
  }
  /// Called once the engine is ready, before a new flow can create a pairing.
  /// Only a saved completion marker establishes legacy setup completion.
  func resolve(legacyDone: Bool, paired: Bool) {
    guard record == nil else { return }
    update {
      $0.completed = legacyDone
      $0.notificationHandled = legacyDone
      if paired && !legacyDone { $0.step = "photos" }
    }
  }
  func leave() { update { $0.completed = true } }
  func handleNotification() { update { $0.notificationHandled = true } }
  func shouldInvite(ready: Bool, receiver: String?, published: Int) -> Bool {
    guard let record else { return false }
    return ready && record.completed && !record.notificationHandled
      && record.receiver == receiver && published > 0
  }

  /// Reapply submitted setup intent after interrupted registration or a later
  /// permission grant. Existing core membership is reused, never re-enumerated.
  @discardableResult func registerScope(model: BackupModel) async -> Bool {
    guard !applyingScope, let record, record.scopeRegistered != true,
      let earlier = record.earlierPhotos, model.ready,
      let receiver = record.receiver, model.pairing?.receiverID == receiver else { return self.record?.scopeRegistered == true }
    let access = BackupEnvironment.photoAccess()
    guard access == .full || access == .limited else { return false }
    applyingScope = true; scopeError = nil
    defer { applyingScope = false }
    await model.setAutoBackup(record.autoBackup)
    if let error = model.autoBackupError { scopeError = error; return false }
    if earlier {
      await model.refreshHistoricalImport(clearError: true)
      if let error = model.historyError { scopeError = error; return false }
      if model.historicalImport == nil { await model.controlHistoricalImport("start") }
      if let error = model.historyError { scopeError = error; return false }
    }
    guard model.pairing?.receiverID == receiver else { return false }
    guard await model.setPaused(false) else { scopeError = model.pauseError; return false }
    update { $0.scopeRegistered = true }
    return true
  }
}

/// First run on iPhone (design/flows.md §1), retained through confirmed Photos
/// publication or explicit departure. Every decision survives process restart.
struct IOSOnboarding: View {
  enum Step: String, CaseIterable { case welcome, install, connect, connected, photos, choose, first }

  @ObservedObject var model: BackupModel
  var finish: () -> Void = {}
  @ObservedObject var progress: IOSFirstRunProgress
  private var step: Step { Step(rawValue: progress.record?.step ?? "") ?? .welcome }
  private var autoBackup: Binding<Bool> {
    Binding(get: { progress.record?.autoBackup ?? true }, set: { value in progress.update { $0.autoBackup = value } })
  }
  @State private var elapsed = false
  @State private var choiceError: String?
  @StateObject private var scanner = IOSPixelScannerState()
  @State private var working = false
  @State private var landed = false
  /// The title follows the flight, so it never claims the photo landed before the user sees it land.
  @State private var announced = false
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let downloadPage = "https://backupduck.app/#download"

  init(model: BackupModel, progress: IOSFirstRunProgress, finish: @escaping () -> Void = {}) {
    self.model = model
    self.finish = finish
    self.progress = progress
  }

  var body: some View {
    VStack(spacing: 0) {
      if step != .welcome {
        DuckStepProgress(current: step == .install ? 1 : [.connect, .connected].contains(step) ? 2 : 3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, DuckSpacing.large).padding(.top, DuckSpacing.xLarge)
          .padding(.bottom, DuckSpacing.medium)
          .frame(maxWidth: 520).frame(maxWidth: .infinity)
      }
      ScrollView {
        content.frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, DuckSpacing.large)
          .padding(.top, step == .welcome ? DuckSpacing.xLarge : 0)
          .frame(maxWidth: 520).frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      actions.padding(.horizontal, 24).padding(.bottom, 16).frame(maxWidth: 520)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(DuckRole.background.ignoresSafeArea())
    .tint(DuckRole.accent)
    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
    .onAppear { if step == .first { checkLanded() } }
    .task(id: progress.record?.firstPhotoStarted) {
      guard step == .first, let started = progress.record?.firstPhotoStarted else { return }
      let remaining = max(0, 20 - Date().timeIntervalSince(started))
      try? await Task.sleep(for: .seconds(remaining))
      if !Task.isCancelled { elapsed = true }
    }
    .onChange(of: model.summary.published) { _, _ in checkLanded() }
    .onChange(of: model.ready) { _, _ in checkLanded() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await progress.registerScope(model: model) } }
    }
    .task { if step == .first { await progress.registerScope(model: model) } }
  }

  // MARK: - Content

  @ViewBuilder private var content: some View {
    switch step {
    case .welcome:
      VStack(spacing: DuckSpacing.xLarge) {
        VStack(spacing: DuckSpacing.medium) {
          DuckIllustration(pose: .welcome, size: 96)
          Text("onboarding_title").font(.largeTitle.weight(.bold))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .accessibilityValue(DuckStepProgress.label(1))
          Text("onboarding_subtitle").font(.body).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
        ViewThatFits(in: .horizontal) {
          welcomeSteps.fixedSize(horizontal: true, vertical: false)
          welcomeSteps
        }.frame(maxWidth: .infinity)
        Text("onboarding_fine_print").font(.caption2).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    case .install:
      VStack(alignment: .leading, spacing: 16) {
        Text("onboarding_install_title").font(.title2.bold())
        Text("onboarding_install_body").foregroundStyle(.secondary)
        VStack(spacing: 8) {
          DuckQRCode(text: Self.downloadPage).frame(width: 200, height: 200).padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20)) // design-exception: QR codes need a white quiet zone in both appearances
          Text(verbatim: "backupduck.app").font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
        }.frame(maxWidth: .infinity).padding(.top, 8)
      }
    case .connect:
      VStack(alignment: .leading, spacing: 16) {
        Text("onboarding_connect_title").font(.title2.bold())
        Text("onboarding_connect_body").foregroundStyle(.secondary)
        IOSPixelScanner(model: model, state: scanner, showsRecoveryActions: false) { go(.connected) }
      }
    case .connected:
      VStack(spacing: 16) {
        DuckIllustration(pose: .pairing, size: 160).padding(.top, 40)
        Text(verbatim: String(format: NSLocalizedString("onboarding_connected_title", comment: ""),
          model.peerDevice?.name ?? "Pixel")).font(.title2.bold()).multilineTextAlignment(.center)
        Text("onboarding_connected_body").foregroundStyle(.secondary).multilineTextAlignment(.center)
      }.frame(maxWidth: .infinity)
    case .photos:
      VStack(alignment: .leading, spacing: 16) {
        Text("onboarding_photos_title").font(.title2.bold())
        VStack(alignment: .leading, spacing: 12) {
          Label("onboarding_photos_direct", systemImage: "arrow.right.circle")
          Label("onboarding_photos_private", systemImage: "lock")
          Label("onboarding_photos_quality", systemImage: "sparkles")
        }.font(.body)
      }
    case .choose:
      VStack(alignment: .leading, spacing: 16) {
        Text("onboarding_choose_title").font(.title2.bold())
        if BackupEnvironment.photoAccess() == .limited { Text("onboarding_access_limited").font(.subheadline).foregroundStyle(.secondary) }
        if let error = choiceError ?? progress.scopeError { Text(error).foregroundStyle(.secondary) }
        VStack(alignment: .leading, spacing: 6) {
          Toggle("onboarding_choose_auto", isOn: autoBackup).font(.headline).toggleStyle(DuckPreferenceToggleStyle())
          Text("onboarding_choose_auto_note").font(.footnote).foregroundStyle(.secondary)
        }.duckCard()
        // Photos lead (visual-language.md): the question shows the user's own photos.
        VStack(alignment: .leading, spacing: 10) {
          OnboardingLibraryStrip()
          Text(earlierQuestion).font(.headline)
          Text("onboarding_choose_earlier_note").font(.footnote).foregroundStyle(.secondary)
        }.duckCard()
      }
    case .first:
      VStack(alignment: .leading, spacing: DuckSpacing.medium) {
        Text(announced ? "onboarding_first_title" : "onboarding_first_heading")
          .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
        FirstPhotoFlight(
          sourceID: firstJob?.asset.source_id,
          senderName: model.deviceSnapshot?.device.name ?? UIDevice.current.localizedModel,
          receiverName: model.peerDevice?.name ?? "Pixel",
          landed: landed
        ) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { announced = true } }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DuckSpacing.medium)
        VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
          if announced {
            Text("onboarding_first_notify").foregroundStyle(.secondary)
          } else {
            Text(firstPhotoMessage)
            if let detail = choiceError ?? blocker?.detail {
              Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var earlierQuestion: String {
    guard let count = BackupEnvironment.libraryCount() else { return NSLocalizedString("onboarding_choose_earlier_unknown", comment: "") }
    return String(format: NSLocalizedString("onboarding_choose_earlier", comment: ""), count.formatted())
  }

  private var welcomeSteps: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.large) {
      stepRow(1, "onboarding_step_install", "onboarding_step_install_note")
      stepRow(2, "onboarding_step_connect", "onboarding_step_connect_note")
      stepRow(3, "onboarding_step_backup", "onboarding_step_backup_note")
    }
  }

  private func stepRow(_ number: Int, _ title: LocalizedStringKey, _ note: LocalizedStringKey) -> some View {
    HStack(alignment: .center, spacing: 12) {
      DuckStepMark(number: number)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(note).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Actions

  @ViewBuilder private var actions: some View {
    VStack(spacing: 8) {
      switch step {
      case .welcome:
        primary("onboarding_start") { go(model.pairing == nil ? .install : .photos) }
      case .install:
        primary("onboarding_install_done") { go(.connect) }
      case .connect:
        if scanner.needsRecovery {
          primary(scanner.cameraFailure == .permission ? "photos_open_settings" : "apple_scan_again") {
            if scanner.cameraFailure == .permission { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            else { scanner.retry() }
          }
        } else { primary("apple_scan_again") {}.hidden().accessibilityHidden(true) }
      case .connected:
        primary("onboarding_continue") { go(.photos) }
      case .photos:
        primary("onboarding_continue") {
          working = true
          Task {
            _ = await model.authorizePhotos()
            progress.update { $0.photoAccess = BackupEnvironment.photoAccess().rawValue }
            working = false; go(.choose)
          }
        }
      case .choose:
        primary("onboarding_choose_all") { Task { await choose(earlier: true) } }
        secondary("onboarding_choose_new_only") { Task { await choose(earlier: false) } }
      case .first:
        if announced {
          primary("onboarding_notify") {
            progress.handleNotification()
            leave()
            Task { await requestFirstRunNotifications() }
          }
          secondary("onboarding_later") { progress.handleNotification(); leave() }
        } else {
          if let blocker, elapsed || blocker.immediate { primary(LocalizedStringKey(blocker.action)) { Task { await recover(blocker) } } }
          else { primary("onboarding_continue") {}.hidden().accessibilityHidden(true) }
          secondary("onboarding_background") { leave() }
        }
      }
      if step != .choose && step != .first {
        secondary("onboarding_later") {}.hidden().accessibilityHidden(true)
      }
    }
  }

  private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).frame(maxWidth: .infinity) }
      .buttonStyle(.borderedProminent).controlSize(.large)
      .disabled(working || progress.applyingScope)
  }

  private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(title, action: action).controlSize(.large)
      .disabled((working || progress.applyingScope) && step != .first)
  }

  private func go(_ next: Step) {
    progress.update {
      $0.step = next.rawValue
      if next == .connected { $0.receiver = model.pairing?.receiverID }
      if next == .first && $0.firstPhotoStarted == nil { $0.firstPhotoStarted = Date() }
    }
    if next == .first { checkLanded() }
  }

  private var firstJob: BackupJob? {
    model.jobs.filter { $0.receiverID == nil || $0.receiverID == progress.record?.receiver }
      .min { $0.id < $1.id }
  }
  private func checkLanded() {
    guard step == .first, !landed, model.ready,
      model.pairing?.receiverID == progress.record?.receiver, model.summary.published > 0 else { return }
    landed = true
  }
  private var firstPhotoMessage: String {
    if let blocker { return blocker.message }
    let key: String
    if model.summary.received > 0 { key = "onboarding_first_saving" }
    else if model.summary.running > 0 || firstJob?.state == "running" { key = "onboarding_first_sending" }
    else { key = "onboarding_first_preparing" }
    return NSLocalizedString(key, comment: "")
  }
  private struct Blocker {
    let message: String
    var detail: String? = nil
    var immediate = false
    let action: String
    enum Recovery { case retryItem(Int64), connection, settings, leave, preparation }
    let recovery: Recovery
  }
  private var blocker: Blocker? {
    guard !landed, model.ready else { return nil }
    if let job = firstJob, job.state == "failed" {
      return Blocker(message: NSLocalizedString("onboarding_first_failed", comment: ""), detail: failureText(job.processingError ?? job.errorCode), immediate: true, action: "retry_task", recovery: .retryItem(job.id))
    }
    if let job = firstJob, job.processing == "failed" {
      // Sender retry cannot restart processing on a received item. Continue to
      // the hub's existing receiver-side recovery instead of offering a no-op.
      return Blocker(message: NSLocalizedString("onboarding_first_save_failed", comment: ""), detail: failureText(job.processingError), immediate: true, action: "onboarding_continue", recovery: .leave)
    }
    // Receipt means the Pixel is saving the photo. A slow publication is not
    // evidence of missing access, empty scope or a failed network send.
    guard model.summary.received == 0, model.summary.running == 0,
      firstJob?.state != "running" else { return nil }
    let access = BackupEnvironment.photoAccess()
    if access == .limited || access == .denied || access == .undetermined {
      return Blocker(
        message: NSLocalizedString(access == .limited ? "onboarding_first_limited" : "onboarding_first_denied", comment: ""),
        detail: NSLocalizedString(access == .limited ? "onboarding_first_limited_note" : "onboarding_first_denied_note", comment: ""),
        action: "photos_open_settings", recovery: .settings)
    }
    if model.waitingForNetwork || model.receiverConnection == .network || model.receiverConnection == .unavailable
      || model.summary.waiting_reason == "network" || model.summary.waiting_reason == "receiver_unavailable" {
      return Blocker(message: NSLocalizedString("onboarding_pixel_unreachable", comment: ""), action: "retry_task", recovery: .connection)
    }
    if let reason = model.preparationReason ?? model.summary.waiting_reason {
      return Blocker(message: NSLocalizedString("onboarding_first_preparing", comment: ""), detail: failureText(reason), action: "retry_task", recovery: .preparation)
    }
    if let error = model.historyError ?? model.autoBackupError {
      return Blocker(message: NSLocalizedString("onboarding_first_failed", comment: ""), detail: error, action: "retry_task", recovery: .preparation)
    }
    if let error = progress.scopeError {
      return Blocker(message: NSLocalizedString("onboarding_first_failed", comment: ""), detail: error, action: "retry_task", recovery: .preparation)
    }
    // A finished empty scan, or a new-photos-only decision with no registered
    // work, establishes the empty state without counting the whole library.
    let emptyScan = model.historicalImport.map { $0.state == "scanned" && $0.checked == 0 && $0.pending == 0 } ?? false
    if (emptyScan || progress.record?.earlierPhotos == false), model.summary.total == 0,
      model.pendingImports == 0, model.discoveryPending == 0, !model.importing {
      return Blocker(message: NSLocalizedString("onboarding_no_photos", comment: ""), action: "onboarding_continue", recovery: .leave)
    }
    return nil
  }
  private func failureText(_ code: String?) -> String {
    if code == "integrity" { return NSLocalizedString("onboarding_first_incomplete", comment: "") }
    let key = "error_" + (code ?? "internal")
    let text = NSLocalizedString(key, comment: "")
    return text == key ? NSLocalizedString("error_internal", comment: "") : text
  }
  private func recover(_ blocker: Blocker) async {
    working = true; choiceError = nil
    switch blocker.recovery {
    case .retryItem(let id):
      if !(await model.retry(id)) { choiceError = model.message }
    case .connection: await model.checkConnection(); await model.becameActive()
    case .settings: openURL(URL(string: UIApplication.openSettingsURLString)!)
    case .leave: leave()
    case .preparation:
      if progress.record?.scopeRegistered != true && progress.record?.earlierPhotos != nil {
        _ = await progress.registerScope(model: model)
      } else if let job = firstJob { _ = await model.retry(job.id) }
      else { await model.processPendingImports(); await model.becameActive() }
    }
    working = false
  }
  private func leave() { progress.leave(); finish() }

  private func choose(earlier: Bool) async {
    working = true; choiceError = nil
    progress.update { $0.earlierPhotos = earlier; $0.receiver = model.pairing?.receiverID; $0.scopeRegistered = false }
    // Persist choices before registering work. Never recreate an existing run.
    let access = BackupEnvironment.photoAccess()
    if access == .full || access == .limited {
      guard await progress.registerScope(model: model) else {
        choiceError = progress.scopeError; working = false; return
      }
    }
    working = false
    go(.first)
  }

}

/// The four most recent photos of the library, as one rounded strip. In the
/// design catalog, which never reads the library, sample pictures stand in.
private struct OnboardingLibraryStrip: View {
  @State private var sources: [String] = []
  var body: some View {
    GeometryReader { geometry in
      let gap: CGFloat = 3
      let side = (geometry.size.width - gap * 3) / 4
      HStack(spacing: gap) {
        ForEach(Array(sources.prefix(4).enumerated()), id: \.offset) { _, id in
          AssetThumbnail(sourceID: id, size: side, cornerRadius: 0)
        }
      }
    }
    .aspectRatio(4, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .task {
      guard BackupEnvironment.usesPhotoLibrary else { sources = (1...4).map { "onboarding-sample-\($0)" }; return }
      let options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.fetchLimit = 4
      let fetch = PHAsset.fetchAssets(with: .image, options: options)
      sources = (0..<fetch.count).map { fetch.object(at: $0).localIdentifier }
    }
  }
}

/// Catalogs inject this boundary instead of displaying a system permission prompt.
@MainActor func requestFirstRunNotifications() async {
  guard BackupEnvironment.usesPhotoLibrary else { return }
  let notifier = BackupEnvironment.activeNotifier()
  notifier.acknowledgeExplanation()
  await notifier.requestPermission()
}

/// Deferred invitation follows the saved photo onto the hub, including cold starts.
struct IOSFirstRunNotificationInvitation: ViewModifier {
  @ObservedObject var progress: IOSFirstRunProgress
  @ObservedObject var model: BackupModel
  @State private var presented = false
  func body(content: Content) -> some View {
    content
      .onChange(of: progress.shouldInvite(ready: model.ready, receiver: model.pairing?.receiverID, published: model.summary.published), initial: true) { _, invite in
        if invite { progress.handleNotification(); presented = true }
      }
      .sheet(isPresented: $presented, onDismiss: { progress.handleNotification() }) {
        DuckSheetLayout(title: "onboarding_notify_title", closeOnly: true, cancel: { progress.handleNotification(); presented = false }) {
          VStack(spacing: 24) {
            Text("onboarding_first_notify")
            Button("onboarding_notify") {
              progress.handleNotification(); presented = false
              Task { await requestFirstRunNotifications() }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("onboarding_later") { progress.handleNotification(); presented = false }
          }
        } actions: { EmptyView() }
      }
  }
}
