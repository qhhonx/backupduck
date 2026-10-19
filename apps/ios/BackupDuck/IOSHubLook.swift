import SwiftUI

/// The hub in the proposed visual language (design/visual-language.md), shown
/// next to today's look while the owner decides it. Same states and actions as
/// `IOSHub`; only the look differs: the user's recent photos lead calm states,
/// one card style, neutral titles with one colored glyph, tinted capsule
/// actions and status pills.
struct IOSHubLook: View {
  @ObservedObject var model: BackupModel
  let status: BackupHubStatus
  let receiverName: String
  var pair: () -> Void
  var offlineHelp: () -> Void
  var open: (LibraryBackupView, String) -> Void
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  @Environment(\.openURL) private var openURL

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        statusSection
        if model.pairing != nil, model.ready, let history = model.historicalImport, history.state != "idle" {
          earlierCard(history)
        }
        if model.pairing != nil, model.ready, !recentSources.isEmpty { recentSection }
      }
      .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
    }
    .background(DuckRole.background)
  }

  // MARK: - Status

  @ViewBuilder private var statusSection: some View {
    switch status {
    case .notPaired:
      duckCard(.empty, "hub_not_paired", note: "hub_not_paired_note") {
        Button(action: pair) { Text("hub_connect").frame(maxWidth: .infinity) }
          .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
      }
    case .opening:
      pill("hub_opening", dot: .secondary)
    case .empty:
      duckCard(.empty, "hub_empty", note: "hub_empty_note") { EmptyView() }
    case .caughtUp(let last, let saving):
      VStack(alignment: .leading, spacing: 6) {
        pill(saving > 0 ? "hub_caught_up_saving" : "hub_caught_up", dot: saving > 0 ? DuckRole.accent : DuckRole.saved)
        if saving > 0 {
          Text(String(format: NSLocalizedString("hub_saving_note", comment: ""), saving.formatted()))
            .font(.subheadline).foregroundStyle(.secondary).padding(.leading, 4)
        } else if let last {
          Text(String(format: NSLocalizedString("hub_last_backup", comment: ""), last.formatted(.relative(presentation: .named))))
            .font(.subheadline).foregroundStyle(.secondary).padding(.leading, 4)
        }
      }
    case .backingUp(let remaining, let bytes):
      card {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text(String(format: NSLocalizedString("hub_backing_up_count", comment: ""), remaining.formatted()))
              .font(.title3.weight(.semibold))
            Spacer()
            if bytes > 0 {
              Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).font(.subheadline).foregroundStyle(.secondary)
            }
          }
          ProgressView(value: progress).tint(DuckRole.accent)
          if remaining >= 50 {
            Toggle(isOn: $keepScreenAwake) {
              VStack(alignment: .leading, spacing: 2) {
                Text("hub_keep_awake")
                Text("hub_keep_awake_note").font(.footnote).foregroundStyle(.secondary)
              }
            }
          }
          secondary("hub_pause") { Task { await model.setPaused(true) } }.disabled(model.changingPause)
        }
      }
    case .paused:
      problem("pause.circle.fill", DuckRole.accent, "hub_paused", note: "hub_paused_note") {
        secondary("hub_resume") { Task { await model.setPaused(false) } }.disabled(model.changingPause)
      }
    case .problem(let issue):
      problemCard(issue)
    }
  }

  @ViewBuilder private func problemCard(_ issue: BackupHubStatus.Problem) -> some View {
    switch issue {
    case .receiverRejected:
      problem("exclamationmark.octagon.fill", DuckRole.failure, "hub_problem_rejected", note: "hub_problem_rejected_note") {
        secondary("hub_problem_rejected_action", action: pair)
      }
    case .receiverUnreachable:
      problem("wifi.exclamationmark", DuckRole.attention,
        LocalizedStringKey(String(format: NSLocalizedString("hub_problem_offline", comment: ""), receiverName)), note: "hub_problem_offline_note") {
        secondary("hub_problem_offline_action", action: offlineHelp)
      }
    case .receiverFull:
      problem("externaldrive.badge.exclamationmark", DuckRole.attention, "hub_problem_receiver_full", note: "hub_problem_receiver_full_note") { EmptyView() }
    case .phoneFull:
      problem("iphone.gen3.badge.exclamationmark", DuckRole.attention, "hub_problem_phone_full", note: "hub_problem_phone_full_note") { EmptyView() }
    case .photoAccessDenied:
      problem("photo.badge.exclamationmark", DuckRole.attention, "hub_problem_photos", note: "hub_problem_photos_note") {
        secondary("hub_problem_photos_action") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
      }
    case .conversionNeeded(let count):
      problem("livephoto", DuckRole.attention,
        LocalizedStringKey(String(format: NSLocalizedString("hub_problem_convert", comment: ""), count.formatted())), note: "hub_problem_convert_note") {
        secondary("hub_problem_convert_action") { open(.needsYou, "attention") }
      }
    }
  }

  // MARK: - Recent photos (P1: photos lead)

  /// Photos the Pixel has received, newest change first.
  private var recentSources: [String] {
    model.jobs.filter { $0.state == "received" }
      .sorted { ($0.stateChangedAt ?? 0) > ($1.stateChangedAt ?? 0) }
      .prefix(6).map(\.asset.source_id)
  }

  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("hub_recent").font(.title3.weight(.semibold))
        Spacer()
        let attention = model.summary.count(for: "attention")
        if attention > 0 {
          Button { open(.needsYou, "attention") } label: {
            pillLabel(String(format: NSLocalizedString("hub_needs_you_count", comment: ""), attention.formatted()), dot: DuckRole.attention)
          }.buttonStyle(.plain)
        }
        Button { open(.recent, "all") } label: { pillLabel(NSLocalizedString("hub_see_all", comment: ""), dot: nil) }
          .buttonStyle(.plain)
      }
      if recentSources.count >= 6 { mosaic(recentSources) } else { strip(recentSources) }
    }
  }

  /// Fewer than six photos: one row of equal tiles, never an empty cell.
  private func strip(_ sources: [String]) -> some View {
    GeometryReader { geometry in
      let gap: CGFloat = 3
      let count = CGFloat(max(min(sources.count, 3), 1))
      let side = (geometry.size.width - gap * (count - 1)) / count
      HStack(spacing: gap) {
        ForEach(sources.prefix(3), id: \.self) { AssetThumbnail(sourceID: $0, size: side, cornerRadius: 0) }
      }
    }
    .frame(height: 120)
    .clipShape(RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
  }

  /// One large photo and two small, then three small, inside one rounded card.
  private func mosaic(_ sources: [String]) -> some View {
    GeometryReader { geometry in
      let gap: CGFloat = 3
      let small = (geometry.size.width - gap * 2) / 3
      let large = small * 2 + gap
      VStack(spacing: gap) {
        HStack(spacing: gap) {
          tile(sources, 0, large)
          VStack(spacing: gap) { tile(sources, 1, small); tile(sources, 2, small) }
        }
        HStack(spacing: gap) { tile(sources, 3, small); tile(sources, 4, small); tile(sources, 5, small) }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
  }

  @ViewBuilder private func tile(_ sources: [String], _ index: Int, _ side: CGFloat) -> some View {
    if index < sources.count {
      AssetThumbnail(sourceID: sources[index], size: side, cornerRadius: 0)
    } else {
      Rectangle().fill(DuckRole.groupedSurface).frame(width: side, height: side)
    }
  }

  // MARK: - Earlier photos

  private func earlierCard(_ history: HistoricalImportStatus) -> some View {
    card {
      VStack(alignment: .leading, spacing: 10) {
        Text("hub_earlier").font(.headline)
        if history.state == "scanned" && history.pending == 0 {
          Label("hub_earlier_done", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
        } else {
          Text(String(format: NSLocalizedString("hub_earlier_progress", comment: ""), history.checked.formatted(), history.pending.formatted()))
            .font(.subheadline).foregroundStyle(.secondary)
          secondary(history.state == "paused" ? "hub_resume" : "hub_pause") {
            Task { await model.controlHistoricalImport(history.state == "paused" ? "resume" : "pause") }
          }.disabled(model.changingHistory)
        }
      }
    }
  }

  // MARK: - Building blocks (visual-language.md § Proposal)

  private var progress: Double {
    let active = model.jobs.filter { ["queued", "running", "waiting", "received"].contains($0.state) }
    let total = active.reduce(UInt64(0)) { $0 + $1.totalBytes }
    let confirmed = active.reduce(UInt64(0)) { $0 + min($1.confirmedBytes, $1.totalBytes) }
    return total == 0 ? 0 : Double(confirmed) / Double(total)
  }

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content().duckLookCard()
  }

  /// A problem: one colored glyph, a neutral title, the note, at most one action.
  private func problem<Action: View>(_ symbol: String, _ tone: Color, _ title: LocalizedStringKey, note: LocalizedStringKey,
    @ViewBuilder action: () -> Action) -> some View {
    card {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: symbol).font(.title3).foregroundStyle(tone).frame(width: 28)
        VStack(alignment: .leading, spacing: 6) {
          Text(title).font(.headline)
          Text(note).font(.subheadline).foregroundStyle(.secondary)
          action().padding(.top, 4)
        }
      }
    }
  }

  private func duckCard<Action: View>(_ pose: DuckIllustration.Pose, _ title: LocalizedStringKey, note: LocalizedStringKey,
    @ViewBuilder action: () -> Action) -> some View {
    card {
      VStack(spacing: 10) {
        DuckIllustration(pose: pose, size: 140)
        Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
        Text(note).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        action().padding(.top, 8)
      }
      .frame(maxWidth: .infinity).padding(.vertical, 12)
    }
  }

  private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    DuckLookSecondaryButton(title, action: action)
  }

  private func pill(_ title: LocalizedStringKey, dot: Color) -> some View {
    DuckLookPill(title: Text(title), dot: dot, prominent: true)
  }

  private func pillLabel(_ title: String, dot: Color?) -> some View {
    DuckLookPill(title: Text(verbatim: title), dot: dot)
  }
}
