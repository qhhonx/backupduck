import SwiftUI

/// Backup history as a photo timeline (design/records.md): problems grouped by
/// cause, then every photo as a tile grouped by the day of its latest change.
/// Shared by iPhone and Mac; replaces the legacy records list in the catalog's
/// proposed design.

/// One photo in the history: a transfer, or a photo still being prepared.
struct HistoryPhoto: Identifiable, Equatable {
  let id: String
  let cursor: Int64
  let sortValue: Int64?
  let source: String
  let job: BackupJob?
  let preparationError: String?

  init?(_ item: BackupTaskItem) {
    id = item.id; cursor = item.cursor; sortValue = item.sort_value
    if let job = item.job {
      self.job = job; source = job.asset.source_id; preparationError = nil
    } else if let preparation = item.preparation {
      job = nil; source = preparation.source; preparationError = preparation.error_code
    } else { return nil }
  }

  enum Mark: Equatable { case saved, sending, saving, needsYou }

  /// The tile mark: nothing when the photo is in the Pixel's Photos.
  var mark: Mark {
    guard let job else { return preparationError == nil || ["local_cache_budget", "local_free_space"].contains(preparationError!) ? .sending : .needsYou }
    if job.state == "failed" { return .needsYou }
    guard job.state == "received" else { return .sending }
    switch job.processing {
    case "complete": return .saved
    case "failed": return .needsYou
    default: return .saving
    }
  }

  var cause: HistoryCause? {
    guard mark == .needsYou else { return nil }
    if let job {
      if job.processingError == "conversion_required" { return .liveConversion }
      if job.state == "received" { return .pixelSave }
      if job.errorCode == "integrity" { return .incomplete }
      if job.errorCode == "source_unavailable" { return .originalUnavailable }
      return .notSent
    }
    return .originalUnavailable
  }

  /// When it last changed, for day grouping.
  var changedAt: Date? {
    (job?.stateChangedAt ?? sortValue).map { Date(timeIntervalSince1970: Double($0) / 1000) }
  }
  var takenAt: Date? {
    job?.asset.metadata?["created_at_ms"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
  }
}

/// Why photos need the user, in the order the page lists them.
enum HistoryCause: Int, CaseIterable, Identifiable {
  case liveConversion, incomplete, notSent, originalUnavailable, pixelSave
  var id: Int { rawValue }
  var title: String {
    switch self {
    case .liveConversion: "records_cause_live"
    case .incomplete: "records_cause_incomplete"
    case .notSent: "records_cause_not_sent"
    case .originalUnavailable: "records_cause_original"
    case .pixelSave: "records_cause_pixel"
    }
  }
  var note: LocalizedStringKey {
    switch self {
    case .liveConversion: "records_cause_live_note"
    case .incomplete, .notSent: "records_cause_retry_note"
    case .originalUnavailable: "records_cause_original_note"
    case .pixelSave: "records_cause_pixel_note"
    }
  }
  /// The same explanation for a single photo, in its detail.
  var detailNote: LocalizedStringKey {
    switch self {
    case .liveConversion: "design_conversion_kept"
    case .incomplete, .notSent: "records_detail_retry_note"
    case .originalUnavailable: "records_detail_original_note"
    case .pixelSave: "records_detail_pixel_note"
    }
  }
  var symbol: String {
    switch self {
    case .liveConversion: "livephoto"
    case .incomplete, .notSent: "arrow.clockwise"
    case .originalUnavailable: "icloud.slash"
    case .pixelSave: "exclamationmark.triangle"
    }
  }
  /// Whether this device can fix it by sending again.
  var retries: Bool { self == .incomplete || self == .notSent || self == .originalUnavailable }
}

@MainActor final class BackupHistoryModel: ObservableObject {
  @Published private(set) var photos: [HistoryPhoto] = []
  @Published private(set) var attention: [HistoryPhoto] = []
  @Published private(set) var total = 0
  @Published private(set) var hasMore = false
  @Published private(set) var loading = false
  @Published private(set) var failed = false
  private var receiver: String?
  private var generation = 0
  static let pageSize = 200

  private struct Page: Decodable { let items: [BackupTaskItem]; let summary: SenderSummary }

  func reload(receiver: String?) async {
    self.receiver = receiver
    generation += 1
    let current = generation
    guard let receiver else { photos = []; attention = []; total = 0; return }
    loading = true; failed = false
    do {
      let first = try await page(receiver: receiver, state: "all", after: nil)
      let problems = try await page(receiver: receiver, state: "attention", after: nil)
      guard current == generation else { return }
      photos = first.items.compactMap(HistoryPhoto.init)
      attention = problems.items.compactMap(HistoryPhoto.init)
      total = first.summary.total
      hasMore = first.items.count == Self.pageSize
    } catch { if current == generation { failed = true } }
    if current == generation { loading = false }
  }

  func loadMore() async {
    guard hasMore, !loading, let receiver, let last = photos.last else { return }
    let current = generation
    loading = true
    defer { if current == generation { loading = false } }
    do {
      let next = try await page(receiver: receiver, state: "all", after: (last.cursor, last.sortValue ?? 0))
      guard current == generation else { return }
      let known = Set(photos.map(\.id))
      photos += next.items.compactMap(HistoryPhoto.init).filter { !known.contains($0.id) }
      hasMore = next.items.count == Self.pageSize
    } catch { if current == generation { failed = true } }
  }

  private func page(receiver: String, state: String, after: (Int64, Int64)?) async throws -> Page {
    var query: [String: Any] = ["op": "backup_tasks", "receiver_id": receiver, "state": state, "sort": "activity", "descending": true]
    if let after { query["after"] = after.0; query["after_value"] = after.1 }
    return try JSONDecoder().decode(Page.self, from: try await Bridge.call(query))
  }

  var causes: [(HistoryCause, [HistoryPhoto])] {
    let grouped = Dictionary(grouping: attention) { $0.cause ?? .notSent }
    return HistoryCause.allCases.compactMap { cause in grouped[cause].map { (cause, $0) } }
  }

  /// Day groups, newest first.
  var days: [(Date, [HistoryPhoto])] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: photos) { calendar.startOfDay(for: $0.changedAt ?? .distantPast) }
    return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
  }
}

struct BackupHistoryView: View {
  @ObservedObject var model: BackupModel
  @StateObject private var history = BackupHistoryModel()
  @State private var selected: HistoryPhoto?
  @State private var retrying: HistoryCause?
  @Environment(\.dynamicTypeSize) private var textSize
  #if os(iOS)
    private let spacing: CGFloat = 2
    private let minimumTile: CGFloat = 86
  #else
    private let spacing: CGFloat = 4
    private let minimumTile: CGFloat = 112
  #endif

  private var receiverName: String { model.peerDevice?.name ?? "Pixel" }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        Text(String(format: NSLocalizedString("records_scope", comment: ""), receiverName, history.total.formatted()))
          .font(.subheadline).foregroundStyle(.secondary)
          .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        if !history.attention.isEmpty { needsYou }
        if history.failed && history.photos.isEmpty {
          ContentUnavailableView {
            Label("records_load_failed", systemImage: "exclamationmark.triangle")
          } actions: {
            Button("records_try_again") { Task { await reload() } }
          }
        } else if !history.loading && history.photos.isEmpty {
          ContentUnavailableView("records_empty", systemImage: "photo.on.rectangle", description: Text("records_empty_note"))
        }
        ForEach(history.days, id: \.0) { day, photos in
          Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTile), spacing: spacing)], spacing: spacing) {
              ForEach(photos) { photo in
                Button { selected = photo } label: { HistoryTile(photo: photo) }
                  .buttonStyle(.plain)
                  .accessibilityLabel(Text(tileLabel(photo)))
                  .onAppear { if photo.id == history.photos.last?.id { Task { await history.loadMore() } } }
              }
            }
            .padding(.bottom, 20)
          } header: {
            Text(dayTitle(day)).font(.headline)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 16).padding(.vertical, 8)
              .background(DuckRole.background)
          }
        }
        if history.loading && history.photos.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
        if !history.photos.isEmpty {
          // Said once for every photo: cloud backup is Google Photos' fact, not ours (P3).
          Text("records_cloud_footer").font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 20)
        }
      }
    }
    .background(DuckRole.background)
    .task(id: "\(model.pairing?.receiverID ?? "")|\(model.queueRevision)") { await reload() }
    .sheet(item: $selected) { photo in PhotoBackupDetail(photo: photo, model: model) }
  }

  private func reload() async { await history.reload(receiver: model.pairing?.receiverID) }

  private var needsYou: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("records_needs_you").font(.headline).padding(.horizontal, 16)
      ForEach(history.causes, id: \.0) { cause, photos in
        causeCard(cause, photos)
          .padding(14)
          #if os(macOS)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
          #else
            .background(DuckRole.groupedSurface, in: RoundedRectangle(cornerRadius: 14))
          #endif
          .padding(.horizontal, 16)
      }
    }
    .padding(.bottom, 24)
  }

  /// Cause, count, a few photos and at most one action. At accessibility sizes
  /// the action moves below the text so the words keep the full width.
  private func causeCard(_ cause: HistoryCause, _ photos: [HistoryPhoto]) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: cause.symbol).foregroundStyle(DuckRole.attention).font(.title3)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: NSLocalizedString(cause.title, comment: ""),
          photos.count >= BackupHistoryModel.pageSize ? "\(BackupHistoryModel.pageSize)+" : photos.count.formatted()))
          .font(.subheadline.weight(.semibold))
        Text(cause.note).font(.footnote).foregroundStyle(.secondary)
        HStack(spacing: 6) {
          ForEach(photos.prefix(5)) { photo in
            Button { selected = photo } label: { HistoryTile(photo: photo, showsMark: false).frame(width: 40, height: 40) }
              .buttonStyle(.plain)
          }
        }.padding(.top, 4)
        if cause.retries && textSize.isAccessibilitySize { retryButton(cause, photos).padding(.top, 6) }
      }
      if cause.retries && !textSize.isAccessibilitySize {
        Spacer(minLength: 8)
        retryButton(cause, photos)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func retryButton(_ cause: HistoryCause, _ photos: [HistoryPhoto]) -> some View {
    Button("records_try_again") {
      retrying = cause
      Task {
        for photo in photos { if let job = photo.job { _ = await model.retry(job.id) } }
        retrying = nil
        await reload()
      }
    }
    .disabled(retrying != nil)
    #if os(iOS)
      .buttonStyle(.bordered).controlSize(.small)
    #endif
  }

  private func dayTitle(_ day: Date) -> String {
    if day == .distantPast { return NSLocalizedString("records_day_unknown", comment: "") }
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return NSLocalizedString("records_today", comment: "") }
    if calendar.isDateInYesterday(day) { return NSLocalizedString("records_yesterday", comment: "") }
    let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
    return day.formatted(sameYear ? .dateTime.month().day().weekday() : .dateTime.year().month().day())
  }

  private func tileLabel(_ photo: HistoryPhoto) -> String {
    let state: String
    switch photo.mark {
    case .saved: state = "records_fact_saved"
    case .sending: state = "records_mark_sending"
    case .saving: state = "records_fact_saving"
    case .needsYou: state = "records_needs_you"
    }
    return NSLocalizedString(state, comment: "")
  }
}

/// A square photo with its backup mark in the corner.
struct HistoryTile: View {
  let photo: HistoryPhoto
  var showsMark = true

  var body: some View {
    GeometryReader { geometry in
      AssetThumbnail(sourceID: photo.source, size: geometry.size.width, cornerRadius: 0)
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: showsMark ? 2 : 6))
    .overlay(alignment: .bottomTrailing) { if showsMark { mark.padding(5) } }
    .overlay(alignment: .bottomLeading) {
      if showsMark, photo.job?.asset.kind == "video" || photo.job?.asset.kind == "motion" {
        Image(systemName: photo.job?.asset.kind == "video" ? "video.fill" : "livephoto")
          .font(.caption2.weight(.semibold)).foregroundStyle(.white).shadow(radius: 2) // design-exception: glyph over a photo
          .padding(5)
      }
    }
    .contentShape(Rectangle())
  }

  /// design/library.md § Tile marks: white glyphs with a soft shadow, like the
  /// media marks; nothing once the Pixel has the photo.
  @ViewBuilder private var mark: some View {
    switch photo.mark {
    case .saved: EmptyView()
    case .sending, .saving: glyph(photo.mark == .sending ? "arrow.up" : "clock")
    case .needsYou: glyph("exclamationmark.triangle.fill")
    }
  }

  private func glyph(_ symbol: String) -> some View {
    Image(systemName: symbol).font(.caption.weight(.semibold))
      .foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 2, y: 0.5)  // design-exception: tile marks on photos (library.md)
  }
}

/// One photo's backup facts (design/records.md § Photo detail): sent, in the
/// Pixel's Photos, and Google Photos, each said separately; unknown stays unknown.
struct PhotoBackupDetail: View {
  let photo: HistoryPhoto
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @State private var retrying = false

  private var receiverName: String {
    photo.job.flatMap { model.receiverDeviceName(for: $0) } ?? model.peerDevice?.name ?? "Pixel"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          GeometryReader { geometry in
            AssetThumbnail(sourceID: photo.source, size: geometry.size.width, cornerRadius: 0)
          }
          .aspectRatio(1, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 14))
          if let taken = photo.takenAt {
            Text(String(format: NSLocalizedString("records_taken", comment: ""), taken.formatted(date: .long, time: .shortened)))
              .font(.subheadline).foregroundStyle(.secondary)
          }
          VStack(alignment: .leading, spacing: 14) {
            sentFact
            photosFact
          }
          if let cause = photo.cause {
            VStack(alignment: .leading, spacing: 10) {
              Text(cause.detailNote).font(.subheadline)
              if cause.retries, let job = photo.job {
                Button {
                  retrying = true
                  Task { _ = await model.retry(job.id); retrying = false; dismiss() }
                } label: { Text("records_try_again").frame(maxWidth: .infinity) }
                  .buttonStyle(.borderedProminent).controlSize(.large).disabled(retrying)
              }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(DuckRole.groupedSurface, in: RoundedRectangle(cornerRadius: 14))
          }
          if let job = photo.job, let file = job.asset.resources.first {
            Text(verbatim: "\(file.filename) · \(ByteCountFormatter.string(fromByteCount: Int64(job.totalBytes), countStyle: .file)) · \(NSLocalizedString("library_filter_" + job.asset.kind, comment: ""))")
              .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
          }
        }
        .padding(20)
      }
      .background(DuckRole.background)
      .navigationTitle("records_detail_title")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("records_done") { dismiss() } } }
    }
    #if os(iOS)
      .presentationDetents([.large])
    #else
      .frame(width: 420, height: 640)
    #endif
  }

  private enum FactState { case done, active, problem, unknown }

  @ViewBuilder private var sentFact: some View {
    let name = receiverName
    if let job = photo.job {
      switch job.state {
      case "received": fact(.done, format("records_fact_sent", name), time: job.stateChangedAt)
      case "failed": fact(.problem, format("records_fact_not_sent", name), status: errorText(job.errorCode))
      case "running": fact(.active, format("records_fact_sending", name))
      case "waiting": fact(.active, format("records_fact_waiting", name), status: NSLocalizedString("state_waiting", comment: ""))
      default: fact(.active, format("records_fact_waiting", name))
      }
    } else if photo.mark == .needsYou {
      fact(.problem, format("records_fact_not_sent", name), status: NSLocalizedString("error_source_unavailable", comment: ""))
    } else {
      fact(.active, format("records_fact_waiting", name), status: NSLocalizedString("records_preparing", comment: ""))
    }
  }

  @ViewBuilder private var photosFact: some View {
    let job = photo.job
    switch (job?.state, job?.processing) {
    case ("received", "complete"): fact(.done, NSLocalizedString("records_fact_saved", comment: ""))
    case ("received", "failed"):
      fact(.problem, NSLocalizedString("records_fact_not_saved", comment: ""),
        status: NSLocalizedString(job?.processingError == "conversion_required" ? "state_conversion_required" : "records_fact_not_saved_note", comment: ""))
    case ("received", _): fact(.active, NSLocalizedString("records_fact_saving", comment: ""))
    default: fact(.unknown, NSLocalizedString("records_fact_not_yet_saved", comment: ""), status: NSLocalizedString("records_after_sent", comment: ""))
    }
  }

  private func format(_ key: String, _ value: String) -> String { String(format: NSLocalizedString(key, comment: ""), value) }

  private func errorText(_ code: String?) -> String {
    guard let code else { return NSLocalizedString("state_failed", comment: "") }
    let key = "error_" + code
    let text = NSLocalizedString(key, comment: "")
    return text == key ? NSLocalizedString("state_failed", comment: "") : text
  }

  private func fact(_ state: FactState, _ title: String, status: String? = nil, time: Int64? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Group {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(DuckRole.saved)
        case .active: Image(systemName: "circle.dotted").foregroundStyle(DuckRole.accent)
        case .problem: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DuckRole.attention)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
      }.font(.body)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.body.weight(.medium))
        if let status { Text(status).font(.subheadline).foregroundStyle(state == .problem ? DuckRole.attention : .secondary) }
        if let time {
          Text(Date(timeIntervalSince1970: Double(time) / 1000).formatted(date: .abbreviated, time: .shortened))
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
    }
  }
}
