import SwiftUI
import Photos
import UniformTypeIdentifiers

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
  let preparationRevision: String?
  let preparationError: String?
  /// The preparation request to retry when there is no transfer yet.
  let preparationRequest: String?

  init?(_ item: BackupTaskItem) {
    id = item.id; cursor = item.cursor; sortValue = item.sort_value
    if let job = item.job {
      self.job = job; source = job.asset.source_id; preparationRevision = nil; preparationError = nil; preparationRequest = nil
    } else if let preparation = item.preparation {
      job = nil; source = preparation.source; preparationRevision = preparation.revision; preparationError = preparation.error_code
      preparationRequest = preparation.id
    } else { return nil }
  }

  init(job: BackupJob) {
    id = "job-\(job.id)"; cursor = job.id; sortValue = job.sortValue
    source = job.asset.source_id; self.job = job; preparationRevision = nil; preparationError = nil; preparationRequest = nil
  }

  enum Mark: Equatable { case saved, sending, saving, needsYou }

  /// The tile mark: nothing when the photo is in the Pixel's Photos.
  var mark: Mark {
    guard let job else { return preparationError == nil || ["local_cache_budget", "local_free_space", "network"].contains(preparationError!) ? .sending : .needsYou }
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
    return preparationError == "source_unavailable" ? .originalUnavailable : .notSent
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
  @Published private(set) var resolved = false
  private var receiver: String?
  private var state = "all"
  private var generation = 0
  static let pageSize = 200

  private struct Page: Decodable { let items: [BackupTaskItem]; let summary: SenderSummary }

  func reload(receiver: String?, state: String = "all") async {
    let sameContext = self.receiver == receiver && self.state == state
    self.receiver = receiver
    self.state = state
    generation += 1
    let current = generation
    guard let receiver else { photos = []; attention = []; total = 0; hasMore = false; failed = false; loading = false; resolved = true; return }
    loading = true; failed = false
    defer { if current == generation { loading = false; if !Task.isCancelled { resolved = true } } }
    do {
      var first = try await page(receiver: receiver, state: state, after: nil)
      // A background state observation refreshes the loaded window, rather than
      // discarding older pages underneath the person's scroll anchor.
      let depth = sameContext ? photos.count : 0
      var items = first.items
      var pageCount = first.items.count
      while items.count < depth, pageCount == Self.pageSize, let last = items.last {
        let next = try await page(receiver: receiver, state: state, after: (last.cursor, last.sort_value ?? 0))
        guard current == generation, !Task.isCancelled else { return }
        let known = Set(items.map(\.id))
        let fresh = next.items.filter { !known.contains($0.id) }
        items += fresh; pageCount = fresh.isEmpty ? 0 : next.items.count
      }
      first = Page(items: items, summary: first.summary)
      let problems = state == "attention" ? first : try await page(receiver: receiver, state: "attention", after: nil)
      guard current == generation, !Task.isCancelled else { return }
      photos = first.items.compactMap(HistoryPhoto.init)
      attention = problems.items.compactMap(HistoryPhoto.init)
      total = first.summary.count(for: state)
      hasMore = pageCount == Self.pageSize
    } catch { if current == generation && !Task.isCancelled { failed = true } }
  }

  func matching(_ target: HistoryPhoto) -> HistoryPhoto? {
    let candidates = photos.filter { candidate in
      guard candidate.source == target.source else { return false }
      if let expected = target.job?.receiverID, let actual = candidate.job?.receiverID { return expected == actual }
      return true
    }
    if let revision = target.job?.asset.revision ?? target.preparationRevision {
      if let exact = candidates.first(where: { $0.id == target.id && ($0.job?.asset.revision ?? $0.preparationRevision) == revision }) { return exact }
      if let matchingRevision = candidates.first(where: { ($0.job?.asset.revision ?? $0.preparationRevision) == revision }) { return matchingRevision }
      return nil
    }
    return candidates.first(where: { $0.id == target.id }) ?? candidates.first
  }

  func loadMore() async {
    guard hasMore, !loading, let receiver, let last = photos.last else { return }
    let current = generation
    loading = true
    defer { if current == generation { loading = false } }
    do {
      let next = try await page(receiver: receiver, state: state, after: (last.cursor, last.sortValue ?? 0))
      guard current == generation else { return }
      let known = Set(photos.map(\.id))
      let fresh = next.items.compactMap(HistoryPhoto.init).filter { !known.contains($0.id) }
      photos += fresh
      if state == "attention" { attention = photos }
      hasMore = !fresh.isEmpty && next.items.count == Self.pageSize
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
  var filter = "all"
  var initialFocus: HistoryPhoto? = nil
  var initialFocusRevision = 0
  var columns: Int? = nil
  var resize: (Int) -> Void = { _ in }
  var mediaFilter: LibraryFilter = .all
  var search = ""
  var clearFilters: () -> Void = {}
  /// The Mac keeps the page mounted for its scroll anchor.
  var active = true
  #if os(macOS)
  @StateObject private var gridState = MacHistoryGridState()
  var visibleRange: MacVisibleRange? = nil
  var selectionChanged: (Int) -> Void = { _ in }
  #endif
  var scopeChanged: (String, Int) -> Void = { _, _ in }
  @StateObject private var history = BackupHistoryModel()
  @StateObject private var photoRouter = BackupPhotoRouter()
  @State private var retrying: HistoryCause?
  @State private var livePhotoHelp = false
  @State private var focusedHistoryID: String?
  @State private var nativePhotoPresented = false
  @Environment(\.dynamicTypeSize) private var textSize


  private var receiverName: String { model.peerDevice?.name ?? "Pixel" }

  var body: some View {
    #if os(macOS)
    MacHistoryGrid(history: history, state: gridState, filter: filter, type: mediaFilter, search: search,
      columns: columns ?? MacLibraryDensity.standard, initialFocus: initialFocus, initialFocusRevision: initialFocusRevision, clearFilters: clearFilters,
      resize: resize, retry: { Task { await reload() } }, active: active)
      .onReceive(gridState.navigation.visibleRange.$title) { title in
        if visibleRange?.title != title { visibleRange?.title = title }
      }
      .onReceive(gridState.$selection) { selectionChanged($0.count) }
      .task(id: "\(model.pairing?.receiverID ?? "")|\(model.queueRevision)|\(filter)") {
        await reload()
      }
    #else
    IOSHistoryGrid(history: history, router: photoRouter, model: model, columns: columns,
      focus: focusedHistoryID, support: AnyView(historySupport), dayTitle: dayTitle,
      presented: { nativePhotoPresented = $0 })
      .ignoresSafeArea(.container)
      .background(Color(uiColor: MediaGridSurface.background))
      .task(id: "\(model.pairing?.receiverID ?? "")|\(model.queueRevision)") {
        await reload()
        if focusedHistoryID == nil, let initialFocus, history.resolved, !history.loading {
          while history.matching(initialFocus) == nil, history.hasMore, !Task.isCancelled {
            let count = history.photos.count
            await history.loadMore()
            if history.photos.count == count { break }
          }
          if !Task.isCancelled { focusedHistoryID = history.matching(initialFocus)?.id }
        }
      }
      .modifier(BackupPhotoPresentation(router: photoRouter, model: model))
      .sheet(isPresented: $livePhotoHelp) { LivePhotoHelpSheet() }
    #endif
  }

  #if os(iOS)
  private var historySupport: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !history.photos.isEmpty {
        Text(String(format: NSLocalizedString(filter == "attention" ? "records_attention_scope" : "records_scope", comment: ""), receiverName, history.total.formatted()))
          .font(.subheadline).foregroundStyle(.secondary)
          .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
      }
      if !history.attention.isEmpty { needsYou }
      if history.failed && history.photos.isEmpty {
        ContentUnavailableView {
          Label("records_load_failed", systemImage: "exclamationmark.triangle")
        } description: { Text("records_empty_note") } actions: {
          Button("records_try_again") { Task { await reload() } }
        }
      } else if history.resolved && !history.loading && history.photos.isEmpty {
        ContentUnavailableView {
          DuckIllustration(pose: .empty, size: 112)
          Text("records_empty")
        } description: { Text("records_empty_note") }
      }
      if (!history.resolved || history.loading) && history.photos.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
    }
  }
  #endif

  private func reload() async {
    #if os(iOS)
    // Do not replace paged history membership under a presented photo.
    guard !nativePhotoPresented, photoRouter.preview == nil, photoRouter.fallback == nil else { return }
    #endif
    await history.reload(receiver: model.pairing?.receiverID, state: filter)
    // An empty page shows only its title; the empty state says the rest.
    scopeChanged(history.photos.isEmpty ? "" : String(format: NSLocalizedString(filter == "attention" ? "records_toolbar_attention" : "records_toolbar_scope", comment: ""), receiverName, history.total.formatted()), history.total)
  }

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
      Image(systemName: cause.symbol).foregroundStyle(DuckRole.attentionGlyph).font(.title3)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: NSLocalizedString(cause.title, comment: ""),
          photos.count >= BackupHistoryModel.pageSize ? "\(BackupHistoryModel.pageSize)+" : photos.count.formatted()))
          .font(.subheadline.weight(.semibold))
        Text(cause.note).font(.footnote).foregroundStyle(.secondary)
        HStack(spacing: 6) {
          ForEach(photos.prefix(5)) { photo in
            BackupPhotoButton(photo: photo, collection: photos, router: photoRouter, surface: .card) { HistoryTile(photo: photo).frame(width: 40, height: 40) }
              .buttonStyle(.plain)
          }
        }.padding(.top, 4)
        if cause.retries && textSize.isAccessibilitySize { retryButton(cause, photos).padding(.top, 6) }
        if cause == .liveConversion && textSize.isAccessibilitySize { livePhotoHelpButton.padding(.top, 6) }
      }
      if cause.retries && !textSize.isAccessibilitySize {
        Spacer(minLength: 8)
        retryButton(cause, photos)
      }
      if cause == .liveConversion && !textSize.isAccessibilitySize {
        Spacer(minLength: 8)
        livePhotoHelpButton
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var livePhotoHelpButton: some View {
    Button("hub_problem_convert_action") { livePhotoHelp = true }
      .buttonStyle(.bordered).controlSize(.small)
  }

  private func retryButton(_ cause: HistoryCause, _ photos: [HistoryPhoto]) -> some View {
    Button("records_try_again") {
      retrying = cause
      Task {
        // Photos still being prepared have no transfer yet; their preparation
        // runs again, and one deleted since then leaves the list.
        for photo in photos {
          if let job = photo.job { _ = await model.retry(job.id) }
          else if let request = photo.preparationRequest { _ = await model.retryPreparation(request) }
        }
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


}

/// A compact problem-card cover; full timeline tiles use the native media cell.
struct HistoryTile: View {
  let photo: HistoryPhoto

  var body: some View {
    GeometryReader { geometry in
      #if os(macOS)
      if let job = photo.job, job.asset.metadata?["source_type"] == "folder" {
        MacTransferThumbnail(job: job, size: geometry.size.width, cornerRadius: 0, fillsFrame: true)
      } else {
        AssetThumbnail(sourceID: photo.source, size: geometry.size.width, cornerRadius: 0)
      }
      #else
      AssetThumbnail(sourceID: photo.source, size: geometry.size.width, cornerRadius: 0)
      #endif
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .contentShape(Rectangle())
  }
}

/// One photo's backup facts (design/records.md § Photo detail): sent, in the
/// Pixel's Photos, and Google Photos, each said separately; unknown stays unknown.
struct PhotoBackupDetail: View {
  let photo: HistoryPhoto
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  private var receiverName: String {
    photo.job.flatMap { model.receiverDeviceName(for: $0) } ?? model.peerDevice?.name ?? "Pixel"
  }

  var body: some View {
    #if os(iOS)
    IOSRecordedPhotoViewer(photo: photo, model: model) { dismiss() }.ignoresSafeArea()
    #else
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          GeometryReader { geometry in
            AssetThumbnail(sourceID: photo.source, size: geometry.size.width, cornerRadius: 0)
          }
          .aspectRatio(1, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 14))
          PhotoInformationLayout(takenAt: photo.takenAt, job: photo.job,
            receiverName: receiverName, needsYou: photo.mark == .needsYou,
            filename: photo.job?.asset.resources.first?.filename ?? "",
            fields: PhotoInformationLayout.fileFields(for: photo.job), model: model)
        }
        .padding(20)
      }
      .background(DuckRole.background)
      .navigationTitle("records_detail_title")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("records_done") { dismiss() }
        }
      }
    }
    .frame(width: 420, height: 640)
    #endif
  }
}

/// The two facts about one photo (design/records.md § Photo detail): sent to the
/// Pixel, and in the Pixel's Photos, each with its time when known. Google
/// Photos' state is never shown per photo (P3).
struct PhotoBackupFacts: View {
  let job: BackupJob?
  let receiverName: String
  var needsYou = false
  var awaitingReceipt = false

  var isAwaitingReceipt: Bool {
    guard let job, ["queued", "running"].contains(job.state),
      job.processing != "failed", !needsYou else { return false }
    return awaitingReceipt || (job.totalBytes > 0 && job.confirmedBytes >= job.totalBytes)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      sentFact
      photosFact
    }
  }

  private enum FactState { case done, active, problem, unknown }

  @ViewBuilder private var sentFact: some View {
    let name = receiverName
    if let job {
      if isAwaitingReceipt {
        fact(.active, NSLocalizedString("photo_viewer_confirming_receipt", comment: ""))
      } else {
        switch job.state {
        case "received": fact(.done, format("records_fact_sent", name), symbol: "clock", time: job.receivedAt ?? job.stateChangedAt)
        case "failed": fact(.problem, format("records_fact_not_sent", name), status: errorText(job.errorCode))
        case "running": fact(.active, format("records_fact_sending", name))
        case "waiting": fact(.active, format("records_fact_waiting", name), status: NSLocalizedString("state_waiting", comment: ""))
        case "paused": fact(.active, format("records_fact_waiting", name), status: NSLocalizedString("state_paused", comment: ""))
        default: fact(.active, format("records_fact_waiting", name))
        }
      }
    } else if needsYou {
      // A preparation failure without its error code does not establish the cause.
      fact(.problem, format("records_fact_not_sent", name), status: NSLocalizedString("state_failed", comment: ""))
    } else {
      fact(.active, format("records_fact_waiting", name), status: NSLocalizedString("records_preparing", comment: ""))
    }
  }

  @ViewBuilder private var photosFact: some View {
    switch (job?.state, job?.processing) {
    case ("received", "complete"): fact(.done, NSLocalizedString("records_fact_saved", comment: ""), time: job?.publishedAt)
    case ("received", "failed"):
      fact(.problem, NSLocalizedString("records_fact_not_saved", comment: ""),
        status: NSLocalizedString(job?.processingError == "conversion_required" ? "state_conversion_required" : "records_fact_not_saved_note", comment: ""))
    case ("received", "pending"): fact(.active, NSLocalizedString("records_fact_saving", comment: ""))
    case ("received", _): fact(.active, NSLocalizedString("photo_viewer_confirming_photos", comment: ""))
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

  private func fact(_ state: FactState, _ title: String, status: String? = nil, symbol: String? = nil, time: Int64? = nil) -> some View {
    let detail = [status, time.map {
      Date(timeIntervalSince1970: Double($0) / 1000).formatted(date: .abbreviated, time: .shortened)
    }].compactMap { $0 }.joined(separator: "\n")
    return HStack(alignment: .firstTextBaseline, spacing: 12) {
      Group {
        switch state {
        case .done: Image(systemName: symbol ?? "checkmark.circle.fill").foregroundStyle(symbol == "clock" ? DuckRole.accent : DuckRole.saved)
        case .active: Image(systemName: "clock").foregroundStyle(DuckRole.accent)
        case .problem: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DuckRole.attentionGlyph)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
      }.font(.body)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.body.weight(.medium))
        // A space retains the same font metrics as a populated supporting line.
        // An empty Text can reserve a shorter line, especially with Dynamic Type.
        Text(verbatim: detail.isEmpty ? " " : detail).font(.subheadline).foregroundStyle(.secondary)
          .lineLimit(1...).fixedSize(horizontal: false, vertical: true)
          .accessibilityHidden(detail.isEmpty)
      }
    }
  }
}

/// A8's content hierarchy, shared by the viewer panel, inspector and unavailable-source detail.
struct PhotoInformationLayout: View {
  let takenAt: Date?
  let job: BackupJob?
  let receiverName: String
  var needsYou = false
  var filename = ""
  var fields: [(String, String)] = []
  @ObservedObject var model: BackupModel
  var loaded = true
  var unavailable = false
  var unpaired = false
  var preparing = false
  var awaitingReceipt = false
  var allowsRetry = true
  var showHistory: (() -> Void)? = nil
  var actionKey: String? = nil
  var actionBusy = false
  var performAction: (() -> Void)? = nil
  var actionFailure: String? = nil
  var backupFacts: AnyView? = nil
  @State private var retrying = false
  @State private var retryFailure: String?
  @State private var followsRetry = false

  private var orderedFields: [(String, String)] {
    let keys = ["preview_file_size", "preview_still_file_size", "preview_format", "preview_resolution",
      "preview_video_duration", "preview_camera", "preview_lens", "preview_aperture", "preview_exposure", "preview_iso"]
    return fields.enumerated().sorted {
      let left = keys.firstIndex(of: $0.element.0) ?? keys.count
      let right = keys.firstIndex(of: $1.element.0) ?? keys.count
      return left == right ? $0.offset < $1.offset : left < right
    }.map(\.element)
  }

  static func fileFields(for job: BackupJob?) -> [(String, String)] {
    guard let job else { return [] }
    var result = [("preview_file_size", ByteCountFormatter.string(fromByteCount: Int64(clamping: job.totalBytes), countStyle: .file))]
    if let name = job.asset.resources.first?.filename,
       let format = UTType(filenameExtension: (name as NSString).pathExtension)?.localizedDescription {
      result.append(("preview_format", format))
    }
    let metadata = job.asset.metadata ?? [:]
    for (key, label) in [("camera_model", "preview_camera"), ("lens_model", "preview_lens"),
      ("aperture", "preview_aperture"), ("exposure", "preview_exposure"), ("iso", "preview_iso")] {
      if let value = metadata[key], !value.isEmpty { result.append((label, value)) }
    }
    return result
  }

  var body: some View {
    let job = job.map { original in
      followsRetry ? model.jobs.first(where: { $0.id == original.id }) ?? original : original
    }
    VStack(alignment: .leading, spacing: DuckSpacing.medium) {
      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
        Text(takenAt.map { $0.formatted(date: .complete, time: .omitted) + " " + $0.formatted(date: .omitted, time: .shortened) }
          ?? NSLocalizedString("design_capture_unknown", comment: ""))
          .font(.subheadline)
        if !filename.isEmpty { Text(verbatim: filename).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
      }.photoInformationCard().accessibilityElement(children: .combine)
      VStack(alignment: .leading, spacing: DuckSpacing.medium) {
        if !loaded { ProgressView().controlSize(.small) }
        else if unavailable { Text("records_load_failed").font(.subheadline).foregroundStyle(.secondary) }
        else if unpaired { Text("hub_not_paired").font(.subheadline).foregroundStyle(.secondary) }
        else if let backupFacts { backupFacts }
        else if job != nil || needsYou || preparing { PhotoBackupFacts(job: job, receiverName: receiverName, needsYou: needsYou, awaitingReceipt: awaitingReceipt) }
        else { Label("library_info_not_backed_up", systemImage: "circle.dashed").font(.subheadline).foregroundStyle(.secondary) }
        if let actionKey, let performAction {
          Button(LocalizedStringKey(actionKey), action: performAction)
            .buttonStyle(.bordered).controlSize(.small).disabled(actionBusy)
            .accessibilityIdentifier("preview.info.backup")
        }
        if job != nil, let showHistory {
          Divider()
          Button(action: showHistory) {
            HStack {
              Label("library_context_history", systemImage: "clock.arrow.circlepath")
              Spacer(minLength: DuckSpacing.small)
              Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
          }.buttonStyle(.plain).foregroundStyle(DuckRole.accent)
            .accessibilityIdentifier("preview.info.history")
        }
        if allowsRetry, let job, job.state == "failed" {
          Button("records_try_again") {
            retrying = true; retryFailure = nil
            Task {
              if await model.retry(job.id) { followsRetry = true }
              else { retryFailure = model.message ?? NSLocalizedString("state_failed", comment: "") }
              retrying = false
            }
          }.buttonStyle(.bordered).disabled(retrying)
        }
        if let failure = actionFailure ?? retryFailure { Text(failure).font(.subheadline).foregroundStyle(.secondary) }
      }.photoInformationCard()
      if !orderedFields.isEmpty {
        VStack(alignment: .leading, spacing: DuckSpacing.small) {
          ForEach(Array(orderedFields.enumerated()), id: \.offset) { _, field in
            LabeledContent(LocalizedStringKey(field.0)) { Text(verbatim: field.1) }
              .fixedSize(horizontal: false, vertical: true)
          }
        }.font(.footnote).foregroundStyle(.secondary).photoInformationCard()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(DuckRole.primaryText).textSelection(.enabled)
    .onChange(of: self.job?.id) { _, _ in followsRetry = false; retryFailure = nil }
  }
}

private extension View {
  @ViewBuilder func photoInformationCard() -> some View {
    #if os(iOS)
    self.frame(maxWidth: .infinity, alignment: .leading)
      .padding(DuckSpacing.medium)
      .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: DuckRadius.card))
    #else
    self.duckCard()
    #endif
  }
}

/// Load the current source observation without replacing a missing fact with an inferred one.
struct PhotoBackupInfo: View {
  let sourceID: String
  var takenAt: Date?
  var filename = ""
  var fields: [(String, String)] = []
  @State private var job: BackupJob?
  @State private var loaded = false
  @State private var unavailable = false
  @ObservedObject private var model = BackupEnvironment.activeModel()

  var body: some View {
    PhotoInformationLayout(takenAt: takenAt, job: job,
      receiverName: job.flatMap { model.receiverDeviceName(for: $0) } ?? model.peerDevice?.name ?? "Pixel",
      filename: filename, fields: fields, model: model, loaded: loaded, unavailable: unavailable, unpaired: model.pairing == nil)
      .task(id: "\(sourceID)|\(model.pairing?.receiverID ?? "")|\(model.queueRevision)") {
        job = nil; loaded = false; unavailable = false
        guard let receiver = model.pairing?.receiverID else { loaded = true; return }
        do {
          let data = try await Bridge.call(["op": "source_job", "receiver_id": receiver, "source_id": sourceID])
          let result = try JSONDecoder().decode(BackupJob?.self, from: data)
          guard !Task.isCancelled else { return }
          job = result
        } catch { if !Task.isCancelled { unavailable = true } }
        if !Task.isCancelled { loaded = true }
      }
  }
}

/// History keeps its lazy timeline mounted while the library viewer owns the media.
enum BackupPhotoSurface {
  case page, card
  #if os(iOS)
  var background: UIColor { self == .card ? DuckRole.groupedSurfaceUIColor : DuckRole.backgroundUIColor }
  #endif
}

@MainActor final class BackupPhotoRouter: ObservableObject {
  let library = PhotoLibraryModel()
  @Published var fallback: HistoryPhoto?
  #if os(iOS)
  @Published var preview: IOSPreviewItem?
  @Published var hiddenSource: String?
  var assets: [PHAsset] = []
  private(set) var surface: BackupPhotoSurface = .page
  #endif
  var frames: [String: CGRect] = [:]
  #if os(macOS)
  var macPresent: ((MacViewerRequest) -> Void)?
  #endif

  private func unavailable(_ photo: HistoryPhoto) {
    #if os(iOS)
    fallback = photo
    #else
    if let macPresent { macPresent(.photo(nil, [], photo)) }
    else { MacPhotoViewerWindow.openUnavailable(photo, model: BackupEnvironment.activeModel()) }
    #endif
  }

  #if os(macOS)
  private func openFolder(_ photo: HistoryPhoto, collection: [HistoryPhoto]) async {
    let folders = FolderSources.active
    var context: [FolderPhoto] = []
    for item in collection + (collection.contains(where: { $0.id == photo.id }) ? [] : [photo]) {
      guard let job = item.job, job.asset.metadata?["source_type"] == "folder",
        let source = job.asset.metadata?["source_ref"],
        let entry = try? await folders.previewEntry(source, job: job.id, sourceID: item.source),
        entry.revision == job.asset.revision || job.asset.revision.hasPrefix(entry.revision + "|") else { continue }
      context.append(FolderPhoto(relative: entry.relative, source_id: entry.source_id,
        revision: entry.revision, size: entry.size, media_type: entry.media_type,
        modified_ms: entry.modified_ms, folder_id: source,
        capture_ms: item.takenAt.map { UInt64(max(0, $0.timeIntervalSince1970 * 1000)) } ?? entry.modified_ms,
        date_source: item.takenAt == nil ? "file_modified" : "embedded",
        backup: item.mark == .saved ? "saved" : item.mark == .needsYou ? "needs_you" : "sending",
        saved_at_ms: nil))
    }
    guard let selected = context.first(where: { $0.source_id == photo.source }) else { unavailable(photo); return }
    if let macPresent { macPresent(.folder(selected, context, folders, nil)) }
    else { MacFolderViewer.open(selected, context: context, folders: folders) }
  }
  #endif

  func open(_ photo: HistoryPhoto, collection: [HistoryPhoto], frame: CGRect, surface: BackupPhotoSurface = .page, ownsSourceVacancy: Bool = false) {
    #if os(iOS)
    self.surface = surface
    library.previewOwnsVacancy = ownsSourceVacancy
    if ownsSourceVacancy {
      library.previewVisibility = { [weak self] in self?.hiddenSource = $0 }
    } else { library.previewVisibility = nil }
    #endif
    #if os(macOS)
    if photo.job?.asset.metadata?["source_type"] == "folder" {
      Task { await openFolder(photo, collection: collection) }
      return
    }
    #endif
    guard BackupEnvironment.usesPhotoLibrary else { unavailable(photo); return }
    let sources = Array(Set(collection.map(\.source) + [photo.source]))
    let fetched = PHAsset.fetchAssets(withLocalIdentifiers: sources, options: nil)
    var byID: [String: PHAsset] = [:]
    fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
    guard let asset = byID[photo.source] else { unavailable(photo); return }
    var seen = Set<String>()
    let context = (collection + [photo]).compactMap { byID[$0.source] }.filter { seen.insert($0.localIdentifier).inserted }
    #if os(iOS)
    assets = context.isEmpty ? [asset] : context
    library.previewFrame = { [weak self] in self?.frames[$0] }
    preview = IOSPreviewItem(asset: asset, frame: frame, poster: library.thumbnails.poster(for: asset), background: surface.background)
    #else
    if let macPresent { macPresent(.photo(asset, context.isEmpty ? [asset] : context, photo)) }
    else { MacPhotoViewerWindow.open(asset: asset, library: library, collection: context.isEmpty ? [asset] : context) }
    #endif
  }
}

struct BackupPhotoButton<Content: View>: View {
  #if os(macOS)
  @Environment(\.macViewerPresentation) private var macPresent
  private func openMacPhoto() { router.macPresent = macPresent; router.open(photo, collection: collection, frame: frame) }
  #endif
  let photo: HistoryPhoto
  let collection: [HistoryPhoto]
  @ObservedObject var router: BackupPhotoRouter
  var surface: BackupPhotoSurface = .page
  @ViewBuilder var content: () -> Content
  @State private var frame = CGRect.zero
  var body: some View {
    #if os(iOS)
    Button { router.open(photo, collection: collection, frame: frame, surface: surface) } label: { content() }
      .buttonStyle(DuckMediaButtonStyle()).background(geometry)
    #else
    content().contentShape(Rectangle()).onTapGesture(count: 2, perform: openMacPhoto)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { openMacPhoto() }
      .background(geometry)
    #endif
  }
  private var geometry: some View {
    GeometryReader { proxy in
      Color.clear.onAppear { update(proxy.frame(in: .global)) }
        .onChange(of: proxy.frame(in: .global)) { _, value in update(value) }
    }
  }
  private func update(_ value: CGRect) { frame = value; router.frames[photo.source] = value }
}

struct BackupPhotoPresentation: ViewModifier {
  @ObservedObject var router: BackupPhotoRouter
  let model: BackupModel
  func body(content: Content) -> some View {
    #if os(iOS)
    content.background(IOSRecordedPhotoPresentation(photo: router.fallback, model: model, frame: { router.frames[$0] }, background: router.surface.background) { router.fallback = nil })
      .background(IOSPreviewPresentation(item: router.preview, library: router.library, collection: router.assets) { router.preview = nil })
    #else
    content.sheet(item: $router.fallback) { PhotoBackupDetail(photo: $0, model: model) }
    #endif
  }
}
