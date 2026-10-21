import SwiftUI
import UIKit

/// The Backup tab as the hub (design/flows.md § Every day, § When something goes
/// wrong; interaction.md I2 task center). One state card answers "are my photos
/// safe?", recently saved photos are the evidence, and summary rows open the
/// matching library views. No primary action while calm. Shown in the design
/// catalog until roadmap step 6 replaces `IOSBackupPage`.
struct IOSHub: View {
  @ObservedObject var model: BackupModel
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  @Environment(\.openURL) private var openURL
  @State private var pairing = false
  @State private var offlineHelp = false
  @StateObject private var photoRouter = BackupPhotoRouter()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var records: String?
  @Binding private var notification: BackupNotifier.Route?

  /// Opens a backup view of the library (design/library.md). When set, the
  /// hub's history and needs-you rows go to the library instead of a page.
  var showLibrary: ((LibraryBackupView) -> Void)?

  init(model: BackupModel, records: String? = nil, notification: Binding<BackupNotifier.Route?> = .constant(nil), showLibrary: ((LibraryBackupView) -> Void)? = nil) {
    self.model = model
    self.showLibrary = showLibrary
    _records = State(initialValue: records)
    _notification = notification
  }

  func open(_ view: LibraryBackupView, fallback: String) {
    if let showLibrary { showLibrary(view) } else { records = fallback }
  }

  private var receiverName: String { model.peerDevice?.name ?? "Pixel" }
  private var status: BackupHubStatus { model.hubStatus }
  private var connected: Bool { model.pairing != nil && model.ready }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DuckSpacing.large) {
          if model.pairing != nil { devicePill }
          stateCard
          if connected, !recentSources.isEmpty {
            VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
              DuckSectionHeader(title: "hub_recent", link: "hub_see_all") { open(.recent, fallback: "all") }
              DuckPhotoMosaic(sources: recentSources, frameChanged: { source, frame in
                photoRouter.frames[source] = frame
              }) { source, frame in
                let photos = recentPhotos
                if let photo = photos.first(where: { $0.source == source }) {
                  photoRouter.frames[source] = frame
                  photoRouter.open(photo, collection: photos, frame: frame)
                }
              }
            }
          }
          if connected { summaryRows }
        }
        .padding(.horizontal, DuckSpacing.medium).padding(.top, DuckSpacing.xxSmall).padding(.bottom, DuckSpacing.xLarge)
        .animation(reduceMotion ? nil : .easeOut(duration: DuckMotion.text), value: status)
      }
      .background(DuckRole.background)
      .navigationTitle("nav_backup")
      .navigationDestination(item: $records) { _ in
        BackupHistoryView(model: model).navigationTitle("records_title").navigationBarTitleDisplayMode(.inline)
      }
    }
    .sheet(isPresented: $pairing) { IOSConnectSheet(model: model, reconnect: status == .problem(.receiverRejected)) }
    .sheet(isPresented: $offlineHelp) { offlineHelpSheet.presentationDetents([.medium, .large]) }
    .task(id: model.ready) { if model.ready { await model.refreshHistoricalImport() } }
    .onChange(of: notification, initial: true) { _, route in
      guard let route, route.receiver == model.pairing?.receiverID else { return }
      notification = nil
      switch route.notice {
      case .unreachable: offlineHelp = true
      case .full: records = nil
      case .convert: open(.needsYou, fallback: "attention")
      case .earlier: open(.recent, fallback: "saved")
      }
    }
    .modifier(BackupPhotoPresentation(router: photoRouter, model: model))
    .tint(DuckRole.accent)
  }

  /// The paired Pixel with one dot for the overall state (V1).
  private var devicePill: some View {
    HStack(spacing: 6) {
      Circle().fill(pillTone).frame(width: 8, height: 8)
      Text(verbatim: receiverName).font(.footnote.weight(.semibold))
    }
    .accessibilityElement(children: .combine)
  }

  private var pillTone: Color {
    switch status {
    case .problem: DuckRole.attention
    case .backingUp: DuckRole.accent
    case .caughtUp(_, let saving): saving > 0 ? DuckRole.accent : DuckRole.saved
    default: Color.secondary
    }
  }

  // MARK: - State (I3: one state at a time)

  @ViewBuilder private var stateCard: some View {
    switch status {
    case .notPaired:
      DuckEmptyState(pose: .pairing, title: "hub_not_paired", note: "hub_not_paired_note") {
        Button { pairing = true } label: { Text("hub_connect").frame(maxWidth: .infinity) }.duckPrimaryButton()
      }
    case .opening:
      DuckStateCard(symbol: "hourglass", tone: .secondary, title: Text("hub_opening"))
    case .empty:
      DuckEmptyState(pose: .empty, title: "hub_empty", note: "hub_empty_note") {
        Button("library_show_all") { open(.all, fallback: "all") }.duckPrimaryButton()
      }
    case .caughtUp(let last, let saving):
      DuckStateCard(symbol: saving > 0 ? "clock.fill" : "checkmark.circle.fill", tone: saving > 0 ? DuckRole.accent : DuckRole.saved,
        title: Text(saving > 0 ? "hub_caught_up_saving" : "hub_caught_up"),
        note: saving > 0
          ? Text(String(format: NSLocalizedString("hub_saving_note", comment: ""), saving.formatted()))
          : last.map { Text(String(format: NSLocalizedString("hub_last_backup", comment: ""), $0.formatted(.relative(presentation: .named)))) })
    case .backingUp(let remaining, let bytes):
      VStack(spacing: DuckSpacing.small) {
        DuckStateCard(symbol: "arrow.up.circle.fill", tone: DuckRole.accent,
          title: Text(bytes > 0
            ? String(format: NSLocalizedString("hub_backing_up", comment: ""), remaining.formatted(),
              ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            : String(format: NSLocalizedString("hub_backing_up_count", comment: ""), remaining.formatted())),
          progress: progress, action: {
          DuckTintedButton("hub_pause") { Task { await model.setPaused(true) } }.disabled(model.changingPause)
        })
        if remaining >= 50 {
          Toggle(isOn: $keepScreenAwake) {
            VStack(alignment: .leading, spacing: 2) {
              Text("hub_keep_awake")
              Text("hub_keep_awake_note").font(.footnote).foregroundStyle(.secondary)
            }
          }
          .duckCard()
        }
      }
    case .paused:
      DuckStateCard(symbol: "pause.circle.fill", tone: .secondary, title: Text("hub_paused"), note: Text("hub_paused_note"), action: {
        DuckTintedButton("hub_resume") { Task { await model.setPaused(false) } }.disabled(model.changingPause)
      })
    case .problem(let issue):
      problemCard(issue)
    }
  }

  /// Bytes already confirmed among the jobs the hub knows about.
  private var progress: Double {
    let active = model.jobs.filter { ["queued", "running", "waiting", "received"].contains($0.state) }
    let total = active.reduce(UInt64(0)) { $0 + $1.totalBytes }
    let confirmed = active.reduce(UInt64(0)) { $0 + min($1.confirmedBytes, $1.totalBytes) }
    return total == 0 ? 0 : Double(confirmed) / Double(total)
  }

  // MARK: - Problems (cause, what happens by itself, at most one action)

  @ViewBuilder private func problemCard(_ issue: BackupHubStatus.Problem) -> some View {
    switch issue {
    case .receiverRejected:
      problem("exclamationmark.octagon.fill", DuckRole.failure, Text("hub_problem_rejected"), note: "hub_problem_rejected_note",
        action: "hub_problem_rejected_action") { pairing = true }
    case .receiverUnreachable:
      problem("wifi.exclamationmark", DuckRole.attention,
        Text(String(format: NSLocalizedString("hub_problem_offline", comment: ""), receiverName)), note: "hub_problem_offline_note",
        action: "hub_problem_offline_action") { offlineHelp = true }
    case .receiverFull:
      problem("externaldrive.badge.exclamationmark", DuckRole.attention, Text("hub_problem_receiver_full"), note: "hub_problem_receiver_full_note")
    case .phoneFull:
      problem("iphone.gen3.badge.exclamationmark", DuckRole.attention, Text("hub_problem_phone_full"), note: "hub_problem_phone_full_note")
    case .photoAccessDenied:
      problem("photo.badge.exclamationmark", DuckRole.attention, Text("hub_problem_photos"), note: "hub_problem_photos_note",
        action: "hub_problem_photos_action") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
    case .conversionNeeded(let count):
      problem("livephoto", DuckRole.attention,
        Text(String(format: NSLocalizedString("hub_problem_convert", comment: ""), count.formatted())), note: "hub_problem_convert_note",
        action: "hub_problem_convert_action") { open(.needsYou, fallback: "attention") }
    case .photosNeedYou(let count):
      problem("exclamationmark.triangle.fill", DuckRole.attention,
        Text(String(format: NSLocalizedString("hub_problem_photos_need_you", comment: ""), count.formatted())),
        note: "hub_problem_photos_need_you_note", action: "hub_problem_convert_action") { open(.needsYou, fallback: "attention") }
    }
  }

  private func problem(_ symbol: String, _ tone: Color, _ title: Text, note: LocalizedStringKey,
    action: LocalizedStringKey? = nil, perform: @escaping () -> Void = {}) -> some View {
    DuckStateCard(symbol: symbol, tone: tone, title: title, note: Text(note), action: {
      if let action { DuckTintedButton(action, action: perform) }
    })
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
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          DuckSheetDismissButton(title: "settings_done") { offlineHelp = false }
        }
      }
    }
  }

  // MARK: - Earlier photos, evidence and summaries

  private func earlierSummary(_ history: HistoricalImportStatus) -> some View {
    let done = history.isSaved
    let paused = history.state == "paused"
    return HStack(spacing: 0) {
      summaryRow(Text(done ? "hub_earlier_done" : "hub_earlier"), value: nil,
        symbol: done ? "checkmark.circle.fill" : "clock.arrow.circlepath", tone: done ? DuckRole.saved : DuckRole.accent,
        note: done ? nil : Text(String(format: NSLocalizedString(history.published == nil ? "hub_earlier_preparation_progress" : "hub_earlier_progress", comment: ""),
          history.checked.formatted(), (history.published.map { max(0, history.checked - $0) } ?? history.pending).formatted()))) {
        open(.recent, fallback: "saved")
      }
      if !done && ["scanning", "paused"].contains(history.state) {
        DuckTintedButton(paused ? "hub_resume" : "hub_pause") {
          Task { await model.controlHistoricalImport(paused ? "resume" : "pause") }
        }.disabled(model.changingHistory).padding(.trailing, DuckSpacing.medium)
      }
    }
    .accessibilityIdentifier("hub.earlier_summary")
  }

  /// Photos the Pixel has received, newest change first.
  private var recentPhotos: [HistoryPhoto] {
    var seen = Set<String>()
    return model.jobs.filter { $0.state == "received" }
      .sorted { ($0.stateChangedAt ?? 0) > ($1.stateChangedAt ?? 0) }
      .filter { seen.insert($0.asset.source_id).inserted }.prefix(5).map(HistoryPhoto.init(job:))
  }
  private var recentSources: [String] { recentPhotos.map(\.source) }

  private var summaryRows: some View {
    VStack(spacing: 0) {
      if let history = model.historicalImport, history.state != "idle" {
        earlierSummary(history)
        Divider().padding(.leading, DuckSpacing.medium)
      }
      let attention = model.summary.count(for: "attention")
      if attention > 0 {
        summaryRow(Text(String(format: NSLocalizedString("hub_needs_you_count", comment: ""), attention.formatted())), value: nil,
          symbol: "exclamationmark.triangle.fill", tone: DuckRole.attention) { open(.needsYou, fallback: "attention") }
        Divider().padding(.leading, DuckSpacing.medium)
      }
      summaryRow(Text("records_title"), value: model.summary.total.formatted(), symbol: nil, tone: nil) { open(.recent, fallback: "all") }
    }
    .background(DuckLook.cardSurface, in: RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
  }

  /// V7: a 52 pt navigation row inside a grouped card.
  private func summaryRow(_ title: Text, value: String?, symbol: String?, tone: Color?, note: Text? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: DuckSpacing.small) {
        if let symbol { Image(systemName: symbol).foregroundStyle(tone ?? .secondary).accessibilityHidden(true) }
        VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
          title.foregroundStyle(.primary)
          if let note { note.font(.subheadline).foregroundStyle(.secondary) }
        }
        Spacer()
        if let value { Text(verbatim: value).foregroundStyle(.secondary) }
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
      }
      .padding(.horizontal, DuckSpacing.medium).frame(minHeight: 52).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
