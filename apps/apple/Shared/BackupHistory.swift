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
  let preparationError: String?

  init?(_ item: BackupTaskItem) {
    id = item.id; cursor = item.cursor; sortValue = item.sort_value
    if let job = item.job {
      self.job = job; source = job.asset.source_id; preparationError = nil
    } else if let preparation = item.preparation {
      job = nil; source = preparation.source; preparationError = preparation.error_code
    } else { return nil }
  }

  init(job: BackupJob) {
    id = "job-\(job.id)"; cursor = job.id; sortValue = job.sortValue
    source = job.asset.source_id; self.job = job; preparationError = nil
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
  private var state = "all"
  private var generation = 0
  static let pageSize = 200

  private struct Page: Decodable { let items: [BackupTaskItem]; let summary: SenderSummary }

  func reload(receiver: String?, state: String = "all") async {
    self.receiver = receiver
    self.state = state
    generation += 1
    let current = generation
    guard let receiver else { photos = []; attention = []; total = 0; return }
    loading = true; failed = false
    do {
      let first = try await page(receiver: receiver, state: state, after: nil)
      let problems = state == "attention" ? first : try await page(receiver: receiver, state: "attention", after: nil)
      guard current == generation else { return }
      photos = first.items.compactMap(HistoryPhoto.init)
      attention = problems.items.compactMap(HistoryPhoto.init)
      total = first.summary.count(for: state)
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
      let next = try await page(receiver: receiver, state: state, after: (last.cursor, last.sortValue ?? 0))
      guard current == generation else { return }
      let known = Set(photos.map(\.id))
      photos += next.items.compactMap(HistoryPhoto.init).filter { !known.contains($0.id) }
      if state == "attention" { attention = photos }
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
  var filter = "all"
  var initialFocus: HistoryPhoto? = nil
  @StateObject private var history = BackupHistoryModel()
  @StateObject private var photoRouter = BackupPhotoRouter()
  @State private var retrying: HistoryCause?
  @State private var didFocus = false
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
    ScrollViewReader { position in
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        Text(String(format: NSLocalizedString(filter == "attention" ? "records_attention_scope" : "records_scope", comment: ""), receiverName, history.total.formatted()))
          .font(.subheadline).foregroundStyle(.secondary)
          .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        if filter == "attention" {
          HStack {
            Text("records_needs_you").font(.headline)
            Spacer()
          }.padding(.horizontal, DuckSpacing.medium).padding(.bottom, DuckSpacing.small)
        } else if !history.attention.isEmpty { needsYou }
        if history.failed && history.photos.isEmpty {
          ContentUnavailableView {
            Label("records_load_failed", systemImage: "exclamationmark.triangle")
          } description: { Text("records_empty_note") } actions: {
            Button("records_try_again") { Task { await reload() } }
          }
        } else if !history.loading && history.photos.isEmpty {
          ContentUnavailableView {
            DuckIllustration(pose: .empty, size: 112)
            Text("records_empty")
          } description: { Text("records_empty_note") } actions: {
            Button("records_try_again") { Task { await reload() } }.buttonStyle(.bordered)
          }
        }
        ForEach(history.days, id: \.0) { day, photos in
          Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTile), spacing: spacing)], spacing: spacing) {
              ForEach(photos) { photo in
                BackupPhotoButton(photo: photo, collection: history.photos, router: photoRouter) { HistoryTile(photo: photo) }
                  .buttonStyle(.plain)
                  .id(photo.id)
                  .accessibilityIdentifier("history.photo.\(photo.id)")
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
    .task(id: "\(model.pairing?.receiverID ?? "")|\(model.queueRevision)") {
      await reload()
      if !didFocus, let initialFocus {
        // A deep entry may be beyond the first page; retain the core's ordering.
        while !history.photos.contains(where: { $0.id == initialFocus.id }), history.hasMore, !Task.isCancelled {
          let count = history.photos.count
          await history.loadMore()
          if history.photos.count == count { break }
        }
        await Task.yield()
        position.scrollTo(initialFocus.id, anchor: .top)
        didFocus = true
      } else if !didFocus, filter == "attention", let first = history.photos.first {
        await Task.yield()
        position.scrollTo(first.id, anchor: .top)
        didFocus = true
      }
    }
    .modifier(BackupPhotoPresentation(router: photoRouter, model: model))
    }
  }

  private func reload() async {
    #if os(iOS)
    // Do not replace paged history membership under a presented photo.
    guard photoRouter.preview == nil, photoRouter.fallback == nil else { return }
    #endif
    await history.reload(receiver: model.pairing?.receiverID, state: filter)
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
      Image(systemName: cause.symbol).foregroundStyle(DuckRole.attention).font(.title3)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: NSLocalizedString(cause.title, comment: ""),
          photos.count >= BackupHistoryModel.pageSize ? "\(BackupHistoryModel.pageSize)+" : photos.count.formatted()))
          .font(.subheadline.weight(.semibold))
        Text(cause.note).font(.footnote).foregroundStyle(.secondary)
        HStack(spacing: 6) {
          ForEach(photos.prefix(5)) { photo in
            BackupPhotoButton(photo: photo, collection: photos, router: photoRouter) { HistoryTile(photo: photo, showsMark: false).frame(width: 40, height: 40) }
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
      switch job.state {
      case "received": fact(.done, format("records_fact_sent", name), symbol: "clock", time: job.receivedAt ?? job.stateChangedAt)
      case "failed": fact(.problem, format("records_fact_not_sent", name), status: errorText(job.errorCode))
      case "running": fact(.active, format("records_fact_sending", name))
      case "waiting": fact(.active, format("records_fact_waiting", name), status: NSLocalizedString("state_waiting", comment: ""))
      default: fact(.active, format("records_fact_waiting", name))
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

  private func fact(_ state: FactState, _ title: String, status: String? = nil, symbol: String? = nil, time: Int64? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Group {
        switch state {
        case .done: Image(systemName: symbol ?? "checkmark.circle.fill").foregroundStyle(symbol == "clock" ? DuckRole.accent : DuckRole.saved)
        case .active: Image(systemName: "clock").foregroundStyle(DuckRole.accent)
        case .problem: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DuckRole.attention)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
      }.font(.body)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.body.weight(.medium))
        if let status { Text(status).font(.subheadline).foregroundStyle(.secondary) }
        if let time {
          Text(Date(timeIntervalSince1970: Double(time) / 1000).formatted(date: .abbreviated, time: .shortened))
            .font(.subheadline).foregroundStyle(.secondary)
        }
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
        else if job != nil || needsYou || preparing { PhotoBackupFacts(job: job, receiverName: receiverName, needsYou: needsYou) }
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
@MainActor final class BackupPhotoRouter: ObservableObject {
  let library = PhotoLibraryModel()
  @Published var fallback: HistoryPhoto?
  #if os(iOS)
  @Published var preview: IOSPreviewItem?
  var assets: [PHAsset] = []
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

  func open(_ photo: HistoryPhoto, collection: [HistoryPhoto], frame: CGRect) {
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
    preview = IOSPreviewItem(asset: asset, frame: frame, poster: library.thumbnails.poster(for: asset))
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
  @ViewBuilder var content: () -> Content
  @State private var frame = CGRect.zero
  var body: some View {
    #if os(iOS)
    Button { router.open(photo, collection: collection, frame: frame) } label: { content() }
      .buttonStyle(.plain).background(geometry)
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
    content.background(IOSRecordedPhotoPresentation(photo: router.fallback, model: model) { router.fallback = nil })
      .background(IOSPreviewPresentation(item: router.preview, library: router.library, collection: router.assets) { router.preview = nil })
    #else
    content.sheet(item: $router.fallback) { PhotoBackupDetail(photo: $0, model: model) }
    #endif
  }
}
