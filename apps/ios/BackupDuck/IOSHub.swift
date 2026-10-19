import SwiftUI
import UIKit

/// The Backup tab as the hub (design/flows.md § Every day, § When something goes
/// wrong): one line that answers "are my photos safe?", a problem card when the
/// user is needed, earlier photos as a background task, and records. Preferences
/// live in Settings. Shown in the design catalog until migration step 6
/// replaces `IOSBackupPage`.
struct IOSHub: View {
  @ObservedObject var model: BackupModel
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  @Environment(\.openURL) private var openURL
  @State private var pairing = false
  @State private var offlineHelp = false
  @State private var records: String?

  /// Opens a backup view of the library (design/library.md). When set, the
  /// hub's history and needs-you rows go to the library instead of a page.
  var showLibrary: ((LibraryBackupView) -> Void)?

  init(model: BackupModel, records: String? = nil, showLibrary: ((LibraryBackupView) -> Void)? = nil) {
    self.model = model
    self.showLibrary = showLibrary
    _records = State(initialValue: records)
  }

  func open(_ view: LibraryBackupView, fallback: String) {
    if let showLibrary { showLibrary(view) } else { records = fallback }
  }

  private var receiverName: String { model.peerDevice?.name ?? "Pixel" }

  var body: some View {
    NavigationStack {
      if DesignPreview.proposedLook {
        IOSHubLook(model: model, status: model.hubStatus, receiverName: receiverName,
          pair: { pairing = true }, offlineHelp: { offlineHelp = true }, open: open)
          .navigationTitle("nav_backup")
          .navigationDestination(item: $records) { _ in
            BackupHistoryView(model: model).navigationTitle("records_title").navigationBarTitleDisplayMode(.inline)
          }
      } else {
        currentLook
      }
    }
    .sheet(isPresented: $pairing) { IOSConnectSheet(model: model, reconnect: model.hubStatus == .problem(.receiverRejected)) }
    .sheet(isPresented: $offlineHelp) { offlineHelpSheet.presentationDetents([.medium]) }
    .task(id: model.ready) { if model.ready { await model.refreshHistoricalImport() } }
    .tint(DuckRole.accent)
  }

  private var currentLook: some View {
      List {
        status
        if model.pairing != nil, model.ready, let history = model.historicalImport, history.state != "idle" {
          earlier(history)
        }
        if model.pairing != nil, model.ready { recordsSection }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("nav_backup")
      .navigationDestination(item: $records) { _ in
        BackupHistoryView(model: model).navigationTitle("records_title").navigationBarTitleDisplayMode(.inline)
      }
  }

  // MARK: - Status

  @ViewBuilder private var status: some View {
    switch model.hubStatus {
    case .notPaired:
      hero(.empty, "hub_not_paired", note: Text("hub_not_paired_note")) {
        Button { pairing = true } label: { Text("hub_connect").frame(maxWidth: .infinity) }
          .buttonStyle(.borderedProminent).controlSize(.large)
      }
    case .opening:
      Section { LabeledContent("hub_opening") { ProgressView() } }
    case .problem(let problem):
      problemCard(problem)
    case .paused:
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label("hub_paused", systemImage: "pause.circle.fill").font(.headline)
          Text("hub_paused_note").font(.subheadline).foregroundStyle(.secondary)
        }
        Button("hub_resume") { Task { await model.setPaused(false) } }.disabled(model.changingPause)
      }
    case .backingUp(let remaining, let bytes):
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(bytes > 0
            ? String(format: NSLocalizedString("hub_backing_up", comment: ""), remaining.formatted(),
              ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            : String(format: NSLocalizedString("hub_backing_up_count", comment: ""), remaining.formatted()))
            .font(.headline)
          ProgressView(value: progress).tint(DuckRole.accent)
        }.padding(.vertical, 4)
        if remaining >= 50 {
          Toggle(isOn: $keepScreenAwake) {
            VStack(alignment: .leading, spacing: 2) {
              Text("hub_keep_awake")
              Text("hub_keep_awake_note").font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        Button("hub_pause") { Task { await model.setPaused(true) } }.disabled(model.changingPause)
      }
    case .caughtUp(let last, let saving):
      hero(.waiting, saving > 0 ? "hub_caught_up_saving" : "hub_caught_up", note: saving > 0
        ? Text(String(format: NSLocalizedString("hub_saving_note", comment: ""), saving.formatted()))
        : last.map { Text(String(format: NSLocalizedString("hub_last_backup", comment: ""), $0.formatted(.relative(presentation: .named)))) }
      ) { EmptyView() }
    case .empty:
      hero(.empty, "hub_empty", note: Text("hub_empty_note")) { EmptyView() }
    }
  }

  /// Bytes already confirmed among the jobs the hub knows about.
  private var progress: Double {
    let active = model.jobs.filter { ["queued", "running", "waiting", "received"].contains($0.state) }
    let total = active.reduce(UInt64(0)) { $0 + $1.totalBytes }
    let confirmed = active.reduce(UInt64(0)) { $0 + min($1.confirmedBytes, $1.totalBytes) }
    return total == 0 ? 0 : Double(confirmed) / Double(total)
  }

  private func hero<Action: View>(_ pose: DuckIllustration.Pose, _ title: LocalizedStringKey, note: Text?,
    @ViewBuilder action: () -> Action) -> some View {
    Section {
      VStack(spacing: 10) {
        DuckIllustration(pose: pose, size: 120)
        Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
        if let note { note.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        action().padding(.top, 6)
      }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    .listRowBackground(Color.clear)
  }

  // MARK: - Problems

  @ViewBuilder private func problemCard(_ problem: BackupHubStatus.Problem) -> some View {
    switch problem {
    case .receiverRejected:
      card("hub_problem_rejected", note: "hub_problem_rejected_note", symbol: "exclamationmark.octagon.fill", tone: DuckRole.failure) {
        Button("hub_problem_rejected_action") { pairing = true }
      }
    case .receiverUnreachable:
      card(LocalizedStringKey(String(format: NSLocalizedString("hub_problem_offline", comment: ""), receiverName)),
        note: "hub_problem_offline_note", symbol: "wifi.exclamationmark", tone: DuckRole.attention) {
        Button("hub_problem_offline_action") { offlineHelp = true }
      }
    case .receiverFull:
      card("hub_problem_receiver_full", note: "hub_problem_receiver_full_note", symbol: "externaldrive.badge.exclamationmark", tone: DuckRole.attention) { EmptyView() }
    case .phoneFull:
      card("hub_problem_phone_full", note: "hub_problem_phone_full_note", symbol: "iphone.gen3.badge.exclamationmark", tone: DuckRole.attention) { EmptyView() }
    case .photoAccessDenied:
      card("hub_problem_photos", note: "hub_problem_photos_note", symbol: "photo.badge.exclamationmark", tone: DuckRole.attention) {
        Button("hub_problem_photos_action") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
      }
    case .conversionNeeded(let count):
      card(LocalizedStringKey(String(format: NSLocalizedString("hub_problem_convert", comment: ""), count.formatted())),
        note: "hub_problem_convert_note", symbol: "livephoto", tone: DuckRole.attention) {
        Button("hub_problem_convert_action") { open(.needsYou, fallback: "attention") }
      }
    }
  }

  private func card<Action: View>(_ title: LocalizedStringKey, note: LocalizedStringKey, symbol: String, tone: Color,
    @ViewBuilder action: () -> Action) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Label(title, systemImage: symbol).font(.headline).foregroundStyle(tone)
        Text(note).font(.subheadline).foregroundStyle(.secondary)
      }.padding(.vertical, 4)
      action()
    }
  }

  private var offlineHelpSheet: some View {
    NavigationStack {
      Form {
        Section {
          Label("hub_help_wifi", systemImage: "wifi")
          Label("hub_help_running", systemImage: "iphone.gen3")
          Label("hub_help_vpn", systemImage: "lock.shield")
        }
        Section {
          Button("hub_help_check") { Task { await model.checkConnection(); offlineHelp = false } }
            .disabled(model.checkingConnection)
        }
      }
      .navigationTitle("hub_help_title").navigationBarTitleDisplayMode(.inline)
    }
  }

  // MARK: - Earlier photos and records

  private func earlier(_ history: HistoricalImportStatus) -> some View {
    Section("hub_earlier") {
      if history.state == "scanned" && history.pending == 0 {
        Label("hub_earlier_done", systemImage: "checkmark.circle.fill").foregroundStyle(DuckRole.saved)
      } else {
        LabeledContent {
          if history.state == "paused" { Text("hub_earlier_paused") }
        } label: {
          Text(String(format: NSLocalizedString("hub_earlier_progress", comment: ""), history.checked.formatted(), history.pending.formatted()))
        }
        Button(history.state == "paused" ? "hub_resume" : "hub_pause") {
          Task { await model.controlHistoricalImport(history.state == "paused" ? "resume" : "pause") }
        }.disabled(model.changingHistory)
      }
    }
  }

  private var recordsSection: some View {
    Section {
      let attention = model.summary.count(for: "attention")
      if attention > 0 {
        Button { open(.needsYou, fallback: "attention") } label: {
          LabeledContent("hub_needs_attention", value: attention.formatted())
        }.foregroundStyle(.primary)
      }
      Button { open(.recent, fallback: "all") } label: {
        LabeledContent("records_title", value: model.summary.total.formatted())
      }.foregroundStyle(.primary)
    }
  }
}
