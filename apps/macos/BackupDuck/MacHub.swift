import AppKit
import SwiftUI

/// The Backup destination as the hub, in the Mac dialect: the same states and
/// problem cards as `IOSHub` (design/flows.md § Hub rules) in a grouped form of
/// limited width. Folders join photos as a second source. Shown in the design
/// catalog until migration step 6 replaces `MacBackupPage`.
struct MacHub: View {
  @ObservedObject var model: BackupModel
  @ObservedObject var folders: FolderSources
  var pair: () -> Void
  var sources: () -> Void
  var showTransfers: (String) -> Void
  @State private var offlineHelp = false

  private var receiverName: String { model.peerDevice?.name ?? "Pixel" }

  var body: some View {
    Form {
      status
      if model.pairing != nil, model.ready {
        if let history = model.historicalImport, history.state != "idle" { earlier(history) }
        Section {
          Button(action: sources) {
            LabeledContent("settings_folders") {
              Text(String(format: NSLocalizedString("settings_folders_value", comment: ""), folders.sources.count))
            }
          }.buttonStyle(.plain)
        }
        recordsSection
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .frame(maxWidth: 640)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DuckRole.background)
    .sheet(isPresented: $offlineHelp) { offlineHelpSheet }
    .task(id: model.ready) { if model.ready { await model.refreshHistoricalImport() } }
  }

  // MARK: - Status

  @ViewBuilder private var status: some View {
    switch model.hubStatus {
    case .notPaired:
      hero(.empty, "hub_not_paired", note: Text("hub_not_paired_note")) {
        Button("hub_connect", action: pair).buttonStyle(.borderedProminent).controlSize(.large)
      }
    case .opening:
      Section { LabeledContent("hub_opening") { ProgressView().controlSize(.small) } }
    case .problem(let problem):
      problemCard(problem)
    case .paused:
      card("hub_paused", note: "hub_paused_note", symbol: "pause.circle.fill", tone: DuckRole.accent) {
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
        HStack {
          Spacer()
          Button("hub_pause") { Task { await model.setPaused(true) } }.disabled(model.changingPause)
        }
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
        DuckIllustration(pose: pose, size: 112)
        Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
        if let note { note.foregroundStyle(.secondary).multilineTextAlignment(.center) }
        action().padding(.top, 6)
      }.frame(maxWidth: .infinity).padding(.vertical, 16)
    }
  }

  // MARK: - Problems

  @ViewBuilder private func problemCard(_ problem: BackupHubStatus.Problem) -> some View {
    switch problem {
    case .receiverRejected:
      card("hub_problem_rejected", note: "hub_problem_rejected_note", symbol: "exclamationmark.octagon.fill", tone: DuckRole.failure) {
        Button("hub_problem_rejected_action", action: pair)
      }
    case .receiverUnreachable:
      card(LocalizedStringKey(String(format: NSLocalizedString("hub_problem_offline", comment: ""), receiverName)),
        note: "hub_problem_offline_note", symbol: "wifi.exclamationmark", tone: DuckRole.attention) {
        Button("hub_problem_offline_action") { offlineHelp = true }
      }
    case .receiverFull:
      card("hub_problem_receiver_full", note: "hub_problem_receiver_full_note", symbol: "externaldrive.badge.exclamationmark", tone: DuckRole.attention) { EmptyView() }
    case .phoneFull:
      card("hub_problem_mac_full", note: "hub_problem_phone_full_note", symbol: "internaldrive", tone: DuckRole.attention) { EmptyView() }
    case .photoAccessDenied:
      card("hub_problem_photos", note: "hub_problem_photos_note", symbol: "photo.badge.exclamationmark", tone: DuckRole.attention) {
        Button("hub_problem_photos_action_mac") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") { NSWorkspace.shared.open(url) }
        }
      }
    case .conversionNeeded(let count):
      card(LocalizedStringKey(String(format: NSLocalizedString("hub_problem_convert", comment: ""), count.formatted())),
        note: "hub_problem_convert_note", symbol: "livephoto", tone: DuckRole.attention) {
        Button("hub_problem_convert_action") { showTransfers("attention") }
      }
    }
  }

  private func card<Action: View>(_ title: LocalizedStringKey, note: LocalizedStringKey, symbol: String, tone: Color,
    @ViewBuilder action: () -> Action) -> some View {
    Section {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Image(systemName: symbol).foregroundStyle(tone).font(.title3)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.headline)
          Text(note).foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)
        action()
      }.padding(.vertical, 6)
    }
  }

  private var offlineHelpSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("hub_help_title").font(.title3.weight(.semibold))
      Label("hub_help_wifi_mac", systemImage: "wifi")
      Label("hub_help_running", systemImage: "iphone.gen3")
      Label("hub_help_vpn", systemImage: "lock.shield")
      HStack {
        Spacer()
        Button("onboarding_later") { offlineHelp = false }
        Button("hub_help_check") { Task { await model.checkConnection(); offlineHelp = false } }
          .buttonStyle(.borderedProminent).disabled(model.checkingConnection)
      }.padding(.top, 8)
    }
    .padding(24).frame(width: 420)
  }

  // MARK: - Earlier photos and records

  private func earlier(_ history: HistoricalImportStatus) -> some View {
    Section("hub_earlier") {
      if history.state == "scanned" && history.pending == 0 {
        Label("hub_earlier_done", systemImage: "checkmark.circle.fill").foregroundStyle(DuckRole.saved)
      } else {
        LabeledContent {
          Button(history.state == "paused" ? "hub_resume" : "hub_pause") {
            Task { await model.controlHistoricalImport(history.state == "paused" ? "resume" : "pause") }
          }.disabled(model.changingHistory)
        } label: {
          Text(String(format: NSLocalizedString("hub_earlier_progress", comment: ""), history.checked.formatted(), history.pending.formatted()))
          if history.state == "paused" { Text("hub_earlier_paused") }
        }
      }
    }
  }

  private var recordsSection: some View {
    Section {
      let attention = model.summary.count(for: "attention")
      if attention > 0 {
        Button { showTransfers("attention") } label: {
          LabeledContent("hub_needs_attention", value: attention.formatted())
        }.buttonStyle(.plain)
      }
      Button { showTransfers("all") } label: {
        LabeledContent("records_title", value: model.summary.total.formatted())
      }.buttonStyle(.plain)
    }
  }
}
