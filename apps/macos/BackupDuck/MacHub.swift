import AppKit
import SwiftUI

/// The Backup destination as the hub in the Mac dialect (interaction.md I2 task
/// center): the same states and problems as `IOSHub` (design/flows.md § Hub
/// rules) on the shared components, recently saved photos as evidence, and
/// summary rows. Actions sit at the trailing edge of a card, as on the desktop.
/// Shown in the design catalog until roadmap step 6 replaces `MacBackupPage`.
struct MacHub: View {
  @ObservedObject var model: BackupModel
  @ObservedObject var folders: FolderSources
  var pair: () -> Void
  var sources: () -> Void
  var showTransfers: (String) -> Void
  @State private var offlineHelp = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var receiverName: String { model.peerDevice?.name ?? "Pixel" }
  private var connected: Bool { model.pairing != nil && model.ready }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DuckSpacing.medium) {
        if model.pairing != nil { devicePill }
        status
        if connected, let history = model.historicalImport, history.state != "idle" { earlier(history) }
        if connected, !recentSources.isEmpty {
          VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
            DuckSectionHeader(title: "hub_recent", link: "hub_see_all") { showTransfers("all") }
            DuckPhotoMosaic(sources: recentSources)
          }
        }
        if connected { summaryRows }
      }
      .padding(DuckSpacing.large)
      .frame(maxWidth: 680)
      .frame(maxWidth: .infinity)
      .animation(reduceMotion ? nil : .easeOut(duration: DuckMotion.text), value: model.hubStatus)
    }
    .background(DuckRole.background)
    .sheet(isPresented: $offlineHelp) { offlineHelpSheet }
    .task(id: model.ready) { if model.ready { await model.refreshHistoricalImport() } }
  }

  private var devicePill: some View {
    DuckPill(title: Text(verbatim: receiverName), dot: {
      switch model.hubStatus {
      case .problem: DuckRole.attention
      case .backingUp: DuckRole.accent
      case .caughtUp(_, let saving): saving > 0 ? DuckRole.accent : DuckRole.saved
      default: Color.secondary
      }
    }())
  }

  // MARK: - Status (I3: one state at a time)

  @ViewBuilder private var status: some View {
    switch model.hubStatus {
    case .notPaired:
      DuckEmptyState(pose: .pairing, title: "hub_not_paired", note: "hub_not_paired_note") {
        Button("hub_connect", action: pair).duckPrimaryButton()
      }
    case .opening:
      DuckStateCard(symbol: "hourglass", tone: .secondary, title: Text("hub_opening"))
    case .problem(let problem):
      problemCard(problem)
    case .paused:
      card(Text("hub_paused"), note: "hub_paused_note", symbol: "pause.circle.fill", tone: .secondary,
        action: "hub_resume") { Task { await model.setPaused(false) } }
    case .backingUp(let remaining, let bytes):
      DuckStateCard(symbol: "arrow.up.circle.fill", tone: DuckRole.accent,
        title: Text(bytes > 0
          ? String(format: NSLocalizedString("hub_backing_up", comment: ""), remaining.formatted(),
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
          : String(format: NSLocalizedString("hub_backing_up_count", comment: ""), remaining.formatted())),
        progress: progress, trailing: {
        DuckTintedButton("hub_pause") { Task { await model.setPaused(true) } }.disabled(model.changingPause)
      })
    case .caughtUp(let last, let saving):
      DuckStateCard(symbol: saving > 0 ? "clock.fill" : "checkmark.circle.fill", tone: saving > 0 ? DuckRole.accent : DuckRole.saved,
        title: Text(saving > 0 ? "hub_caught_up_saving" : "hub_caught_up"),
        note: saving > 0
          ? Text(String(format: NSLocalizedString("hub_saving_note", comment: ""), saving.formatted()))
          : last.map { Text(String(format: NSLocalizedString("hub_last_backup", comment: ""), $0.formatted(.relative(presentation: .named)))) })
    case .empty:
      DuckEmptyState(pose: .empty, title: "hub_empty", note: "hub_empty_note") {
        Button("records_title") { showTransfers("all") }.buttonStyle(.bordered)
      }
    }
  }

  private var progress: Double {
    let active = model.jobs.filter { ["queued", "running", "waiting", "received"].contains($0.state) }
    let total = active.reduce(UInt64(0)) { $0 + $1.totalBytes }
    let confirmed = active.reduce(UInt64(0)) { $0 + min($1.confirmedBytes, $1.totalBytes) }
    return total == 0 ? 0 : Double(confirmed) / Double(total)
  }

  // MARK: - Problems (cause, what happens by itself, at most one action)

  @ViewBuilder private func problemCard(_ problem: BackupHubStatus.Problem) -> some View {
    switch problem {
    case .receiverRejected:
      card(Text("hub_problem_rejected"), note: "hub_problem_rejected_note", symbol: "exclamationmark.octagon.fill", tone: DuckRole.failure,
        action: "hub_problem_rejected_action", perform: pair)
    case .receiverUnreachable:
      card(Text(String(format: NSLocalizedString("hub_problem_offline", comment: ""), receiverName)),
        note: "hub_problem_offline_note", symbol: "wifi.exclamationmark", tone: DuckRole.attention,
        action: "hub_problem_offline_action") { offlineHelp = true }
    case .receiverFull:
      card(Text("hub_problem_receiver_full"), note: "hub_problem_receiver_full_note", symbol: "externaldrive.badge.exclamationmark", tone: DuckRole.attention)
    case .phoneFull:
      card(Text("hub_problem_mac_full"), note: "hub_problem_phone_full_note", symbol: "internaldrive", tone: DuckRole.attention)
    case .photoAccessDenied:
      card(Text("hub_problem_photos"), note: "hub_problem_photos_note", symbol: "photo.badge.exclamationmark", tone: DuckRole.attention,
        action: "hub_problem_photos_action_mac") {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") { NSWorkspace.shared.open(url) }
      }
    case .conversionNeeded(let count):
      card(Text(String(format: NSLocalizedString("hub_problem_convert", comment: ""), count.formatted())),
        note: "hub_problem_convert_note", symbol: "livephoto", tone: DuckRole.attention,
        action: "hub_problem_convert_action") { showTransfers("attention") }
    case .photosNeedYou(let count):
      card(Text(String(format: NSLocalizedString("hub_problem_photos_need_you", comment: ""), count.formatted())),
        note: "hub_problem_photos_need_you_note", symbol: "exclamationmark.triangle.fill", tone: DuckRole.attention,
        action: "hub_problem_convert_action") { showTransfers("attention") }
    }
  }

  private func card(_ title: Text, note: LocalizedStringKey, symbol: String, tone: Color,
    action: LocalizedStringKey? = nil, perform: @escaping () -> Void = {}) -> some View {
    DuckStateCard(symbol: symbol, tone: tone, title: title, note: Text(note), trailing: {
      if let action { DuckTintedButton(action, action: perform) }
    })
  }

  private var offlineHelpSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("hub_help_title").font(.title2.bold())
      Label("hub_help_wifi_mac", systemImage: "wifi")
      Label("hub_help_running", systemImage: "iphone.gen3")
      Label("hub_help_vpn", systemImage: "lock.shield")
      HStack {
        Spacer()
        Button("hub_help_check") { Task { await model.checkConnection(); offlineHelp = false } }
          .buttonStyle(.bordered).disabled(model.checkingConnection)
        Button("settings_done") { offlineHelp = false }
          .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }.padding(.top, 8)
    }
    .padding(24).frame(width: 420)
  }

  // MARK: - Earlier photos, evidence and summaries

  private func earlier(_ history: HistoricalImportStatus) -> some View {
    let done = history.state == "scanned" && history.pending == 0
    let paused = history.state == "paused"
    return DuckStateCard(symbol: done ? "checkmark.circle.fill" : "clock.arrow.circlepath", tone: done ? DuckRole.saved : DuckRole.accent,
      title: Text(done ? "hub_earlier_done" : "hub_earlier"),
      note: done ? nil : Text(String(format: NSLocalizedString("hub_earlier_progress", comment: ""),
        history.checked.formatted(), history.pending.formatted())), trailing: {
      if !done {
        DuckTintedButton(paused ? "hub_resume" : "hub_pause") {
          Task { await model.controlHistoricalImport(paused ? "resume" : "pause") }
        }.disabled(model.changingHistory)
      }
    })
  }

  /// Photos the Pixel has received, newest change first.
  private var recentSources: [String] {
    model.jobs.filter { $0.state == "received" }
      .sorted { ($0.stateChangedAt ?? 0) > ($1.stateChangedAt ?? 0) }
      .prefix(5).map(\.asset.source_id)
  }

  private var summaryRows: some View {
    VStack(spacing: 0) {
      let attention = model.summary.count(for: "attention")
      if attention > 0 {
        row(Text(String(format: NSLocalizedString("hub_needs_you_count", comment: ""), attention.formatted())), value: nil,
          symbol: "exclamationmark.triangle.fill") { showTransfers("attention") }
        Divider().padding(.leading, DuckSpacing.small)
      }
      row(Text("records_title"), value: model.summary.total.formatted(), symbol: nil) { showTransfers("all") }
      Divider().padding(.leading, DuckSpacing.small)
      row(Text("settings_folders"), value: String(format: NSLocalizedString("settings_folders_value", comment: ""), folders.sources.count),
        symbol: nil, action: sources)
    }
    .background(DuckLook.cardSurface, in: RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
  }

  /// V7: a 41 pt row inside a grouped card.
  private func row(_ title: Text, value: String?, symbol: String?, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: DuckSpacing.xSmall) {
        if let symbol { Image(systemName: symbol).foregroundStyle(DuckRole.attention).accessibilityHidden(true) }
        title.foregroundStyle(.primary)
        Spacer()
        if let value { Text(verbatim: value).foregroundStyle(.secondary) }
        Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
      }
      .padding(.horizontal, DuckSpacing.small).frame(minHeight: DuckSettingsMetrics.rowHeight).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
