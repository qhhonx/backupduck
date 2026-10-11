import Photos
import SwiftUI

struct AssetThumbnail: View {
  let sourceID: String
  var size: CGFloat = 56
  #if os(macOS)
    @AppStorage("macListThumbnails") private var enabled = true
  #endif
  @State private var image: LibraryImage?
  @State private var request: PHImageRequestID = PHInvalidImageRequestID
  @State private var requestToken = UUID()
  private static let pipeline = ThumbnailPipeline()
  private var requestKey: String {
    #if os(macOS)
      return "\(sourceID)|\(enabled)|\(size)"
    #else
      return "\(sourceID)|\(size)"
    #endif
  }
  var body: some View {
    ZStack {
      Rectangle().fill(.quaternary)
      if let image {
        #if os(macOS)
          Image(nsImage: image).resizable().scaledToFill()
        #else
          Image(uiImage: image).resizable().scaledToFill()
        #endif
      } else {
        Image(systemName: "photo").foregroundStyle(.secondary)
          #if os(iOS)
            .font(.system(size: 22)).symbolVariant(.none)
          #endif
      }
    }.frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
      .task(id: requestKey) {
        Self.pipeline.cancel(request)
        image = nil
        requestToken = UUID()
        let token = requestToken
        #if os(macOS)
          guard enabled else { return }
        #endif
        guard
          let asset = PHAsset.fetchAssets(withLocalIdentifiers: [sourceID], options: photoLibraryFetchOptions())
            .firstObject
        else { return }
        request = Self.pipeline.request(asset, pixels: size * 2) { value, _ in
          guard requestToken == token else { return }
          if let value { image = value }
        }
      }.onDisappear {
        requestToken = UUID()
        Self.pipeline.cancel(request)
      }
  }
}

struct TransferRow: View {
  let job: BackupJob
  var progress: TransferProgress?
  var topInset: CGFloat = 12
  private var displayedBytes: UInt64 {
    guard job.state == "running", let progress else { return job.confirmedBytes }
    return progress.displayedBytes(confirmed: job.confirmedBytes, total: job.totalBytes)
  }
  private var statusKey: String {
    if job.state == "received" {
      switch job.processing {
      case "complete": return "state_published"
      case "failed": return "state_publication_failed"
      case "pending": return "state_publication_pending"
      default: return "apple_gallery_unconfirmed"
      }
    }
    guard job.state == "running" else { return "state_" + job.state }
    if progress?.waitingForNetwork == true { return "waiting_for_wifi" }
    guard let progress, progress.sent > 0 else { return "state_scheduled" }
    return progress.expected > 0 && progress.sent >= progress.expected ? "state_confirming" : "state_running"
  }
  private var statusText: String {
    let error = ["failed", "waiting"].contains(job.state) ? job.errorCode : nil
    var text = NSLocalizedString(error.map { "error_" + $0 } ?? statusKey, comment: "")
    if job.state == "waiting", let next = job.nextAttemptAt, next > 0 {
      text += " · " + String(format: NSLocalizedString("task_retry_time", comment: ""),
        Date(timeIntervalSince1970: Double(next)).formatted(date: .omitted, time: .standard))
    }
    return text
  }
  private var compactStatus: String {
    if job.state == "received" && job.processing == "failed" { return NSLocalizedString("design_status_failed", comment: "") }
    if job.state == "received" && job.processing == "pending" { return NSLocalizedString("design_status_pending", comment: "") }
    if job.state == "received" && job.processing != "complete" { return NSLocalizedString("apple_gallery_unconfirmed", comment: "") }
    if job.state == "waiting" { return NSLocalizedString("state_waiting", comment: "") }
    return statusText
  }
  var activityLabel: String? = nil
  var receiverName: String? = nil
  var retry: () async -> Bool
  @State private var details = false
  private var tone: DuckTone {
    if job.state == "received" {
      if job.processing == "complete" { return .saved }
      if job.processing == "failed" { return .failure }
      return .attention
    }
    if job.state == "failed" { return .failure }
    if job.state == "waiting" { return .attention }
    return job.state == "running" ? .action : .neutral
  }
  private var symbol: String {
    if job.state == "received" {
      return job.processing == "complete" ? "checkmark" : job.processing == "failed" ? "exclamationmark.triangle" : "clock"
    }
    return taskSymbol(job.state)
  }
  #if os(iOS)
  @Environment(\.dynamicTypeSize) private var textSize
  private var thumbnailSize: CGFloat { textSize.isAccessibilitySize ? 48 : 54 }
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  #endif
  var body: some View {
    rowContents
      .contentShape(Rectangle()).onTapGesture { details = true }
      .accessibilityAddTraits(.isButton).accessibilityAction { details = true }
      .overlay(alignment: .bottom) {
        if job.state == "running", let fraction = progress?.activeFraction(confirmed: job.confirmedBytes, total: job.totalBytes) {
          GeometryReader { geometry in
            Rectangle().fill(DuckColors.action).frame(width: geometry.size.width * fraction)
          }.frame(height: 2).accessibilityHidden(true)
        }
      }
      .sheet(isPresented: $details) {
        DuckTransferDetail(job: job, status: statusText, symbol: symbol, tone: tone, receiverName: receiverName, retry: retry)
      }
  }
  @ViewBuilder private var rowContents: some View {
    #if os(iOS)
    HStack(spacing: 12) {
      AssetThumbnail(sourceID: job.asset.source_id, size: thumbnailSize)
      VStack(alignment: .leading, spacing: 5) {
        Text(job.asset.resources.first?.filename ?? "").iosPrototypeText(size: bodySize, weight: .semibold, lineHeight: 1.4)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 6) {
          Text(LocalizedStringKey("library_filter_" + (job.asset.metadata?["burst_group_ref"] != nil ? "burst" : job.asset.kind)))
          if let ms = job.asset.metadata?["created_at_ms"].flatMap(Double.init) {
            Text(Date(timeIntervalSince1970: ms / 1000).formatted(date: .abbreviated, time: .shortened))
          } else { Text("design_capture_unknown") }
        }.iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
        Label(statusText, systemImage: symbol).symbolVariant(.none)
          .iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(tone.color)
          .fixedSize(horizontal: false, vertical: true)
        if let activityLabel {
          Text(NSLocalizedString(activityLabel, comment: "") + " · " + (job.stateChangedAt.map {
            Date(timeIntervalSince1970: Double($0) / 1000).formatted(date: .abbreviated, time: .standard)
          } ?? NSLocalizedString("task_order_unknown", comment: "")))
            .iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.vertical, 12).frame(minHeight: 72)
    #else
    HStack(spacing: 12) {
      #if os(macOS)
        if job.asset.metadata?["source_type"] == "folder" { MacTransferThumbnail(job: job, size: 44) }
        else { AssetThumbnail(sourceID: job.asset.source_id, size: 44) }
      #else
        AssetThumbnail(sourceID: job.asset.source_id, size: 44)
      #endif
      VStack(alignment: .leading, spacing: 5) {
        Text(job.asset.resources.first?.filename ?? "").font(.system(size: 14, weight: .semibold)).lineLimit(1)
        HStack(spacing: 6) {
          Label(LocalizedStringKey("library_filter_" + (job.asset.metadata?["burst_group_ref"] != nil ? "burst" : job.asset.kind)),
            systemImage: job.asset.metadata?["burst_group_ref"] != nil ? "square.stack" : job.asset.kind == "motion" ? "livephoto" : job.asset.kind == "video" ? "video" : "photo")
            .symbolVariant(.none)
          if let activityLabel {
            Text(NSLocalizedString(activityLabel, comment: "") + " · " + (job.stateChangedAt.map {
              Date(timeIntervalSince1970: Double($0) / 1000).formatted(date: .abbreviated, time: .standard)
            } ?? NSLocalizedString("task_order_unknown", comment: "")))
          } else if let milliseconds = job.asset.metadata?["created_at_ms"].flatMap(Double.init) {
            Text(Date(timeIntervalSince1970: milliseconds / 1000).formatted(date: .abbreviated, time: .shortened))
          } else { Text("design_capture_unknown") }
          Text("·")
          Text(job.asset.metadata?["source_name"] ?? NSLocalizedString(job.asset.metadata?["source_type"] == "folder" ? "task_order_unknown" : "source_system_library", comment: ""))
        }.font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 5) {
        DuckStatusBadge(text: compactStatus, symbol: symbol, tone: tone).lineLimit(1).help(statusText)
        Text(ByteCountFormatter.string(fromByteCount: Int64(job.totalBytes), countStyle: .file))
          .font(.caption).foregroundStyle(DuckColors.textSecondary).monospacedDigit()
      }.fixedSize(horizontal: false, vertical: true)
    }.padding(.top, topInset).padding(.bottom, 12)
    #endif
  }
}

/// The sender exposes a receipt transition time, not receiver-internal publish
/// times. Keep these facts separate from capture dates and the current pairing.
struct TransferDetailFacts {
  enum NodeState: Equatable { case confirmed, pending, active, failed }
  let receiptConfirmed: Bool
  let galleryConfirmed: Bool
  let originalNode: NodeState
  let galleryNode: NodeState
  let receiptConfirmedAt: Date?
  var gallerySavedAt: Date? { nil } // No gallery event timestamp in Job JSON.
  var cloudConfirmed: Bool { false } // No Google Photos receipt in this protocol.
  init(job: BackupJob) {
    receiptConfirmed = job.state == "received"
    galleryConfirmed = receiptConfirmed && job.processing == "complete"
    originalNode = receiptConfirmed ? .confirmed : job.state == "running" ? .active : job.state == "failed" ? .failed : .pending
    galleryNode = galleryConfirmed ? .confirmed : receiptConfirmed && job.processing == "failed" ? .failed : .pending
    if receiptConfirmed, let ms = job.stateChangedAt, ms > 0, ms <= 253402300799000 {
      receiptConfirmedAt = Date(timeIntervalSince1970: Double(ms) / 1000)
    } else { receiptConfirmedAt = nil }
  }
}

struct DuckTransferDetail: View {
  let job: BackupJob
  let status: String
  let symbol: String
  let tone: DuckTone
  var receiverName: String? = nil
  var retry: () async -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var retrying = false
  @State private var retrySubmitted = false
  @State private var retryFailed = false
  private var facts: TransferDetailFacts { TransferDetailFacts(job: job) }
  private var targetName: String {
    receiverName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? receiverName! : NSLocalizedString("apple_transfer_receiver_unknown", comment: "")
  }
  private var receiptTime: String {
    facts.receiptConfirmedAt.map {
      String(format: NSLocalizedString("apple_transfer_receipt_time", comment: ""),
        $0.formatted(date: .abbreviated, time: .standard))
    } ?? NSLocalizedString("apple_transfer_receipt_time_unknown", comment: "")
  }
  private var galleryDescription: String {
    NSLocalizedString(!facts.receiptConfirmed ? "apple_gallery_after_receipt"
      : facts.galleryConfirmed ? "state_published"
      : job.processing == "failed" ? "state_publication_failed" : job.processing == "pending" ? "state_publication_pending" : "apple_gallery_unconfirmed", comment: "")
  }
  #if os(iOS)
  @ScaledMetric(relativeTo: .caption) private var markerSize = 8
  private var markerTop: CGFloat { max(6, (bodySize * 1.4 - markerSize) / 2) }
  #else
  private var markerSize: CGFloat { 8 }
  private var markerTop: CGFloat { 6 }
  #endif
  private func timelineMarker(state: TransferDetailFacts.NodeState, last: Bool) -> some View {
    let color: Color = state == .confirmed ? DuckColors.saved : state == .failed ? DuckColors.failure
      : state == .active ? DuckColors.action : DuckColors.textSecondary
    return GeometryReader { geometry in
      if !last {
        Rectangle().fill(DuckColors.border).frame(width: 1, height: max(0, geometry.size.height - markerSize / 2))
          .offset(x: markerSize / 2 - 0.5, y: markerTop + markerSize)
      }
      Circle().fill(state == .confirmed ? color : DuckColors.surface)
        .overlay { Circle().stroke(color, lineWidth: 1) }
        .frame(width: markerSize, height: markerSize).offset(y: markerTop)
    }.frame(width: markerSize).accessibilityHidden(true)
  }
  var body: some View {
    DuckSheetLayout(title: "apple_transfer_stages", busy: retrying, error: retryFailed ? NSLocalizedString("apple_retry_failed", comment: "") : nil) {
      #if os(iOS)
      iosDetails
      #else
      Text(job.asset.resources.first?.filename ?? "").font(.system(size: 16, weight: .semibold))
        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 0) {
        macField("design_file_type", value: NSLocalizedString("library_filter_" + (job.asset.metadata?["burst_group_ref"] == nil ? job.asset.kind : "burst"), comment: ""))
        macField("design_capture_time", value: job.asset.metadata?["created_at_ms"].flatMap(Double.init).map {
          Date(timeIntervalSince1970: $0 / 1000).formatted(date: .abbreviated, time: .shortened)
        } ?? NSLocalizedString("task_order_unknown", comment: ""))
        macField("task_source_filter", value: job.asset.metadata?["source_name"] ?? NSLocalizedString(job.asset.metadata?["source_type"] == "folder" ? "task_order_unknown" : "source_system_library", comment: ""))
        macField("apple_transfer_detail_receiver", value: targetName)
        macField("design_file_size", value: ByteCountFormatter.string(fromByteCount: Int64(job.totalBytes), countStyle: .file))
        macField("mac_fidelity_status_title", value: status)
      }
      VStack(alignment: .leading, spacing: 0) {
        macTimeline(facts.receiptConfirmed ? "apple_transfer_receipt_verified" : "apple_transfer_stage_originals",
          detail: facts.receiptConfirmed ? NSLocalizedString("design_original_retained", comment: "") : status,
          time: receiptTime, state: facts.originalNode)
        macTimeline("apple_transfer_stage_gallery", detail: galleryDescription,
          time: NSLocalizedString("apple_transfer_gallery_time_unknown", comment: ""), state: facts.galleryNode)
        macTimeline("Google Photos", detail: NSLocalizedString("apple_transfer_cloud_note", comment: ""),
          time: NSLocalizedString("apple_transfer_cloud_unknown", comment: ""), state: .pending, last: true)
      }
      if job.processing == "failed" { DuckNotice(title: "design_retry_on_pixel", tone: .attention, symbol: "exclamationmark.circle") }
      if let error = job.processingError ?? job.errorCode {
        DuckNotice(title: LocalizedStringKey(NSLocalizedString("error_" + error, comment: "")), tone: .failure, symbol: "exclamationmark.circle")
      }
      if retrySubmitted { DuckNotice(title: "apple_retry_submitted", tone: .action, symbol: "clock") }
      #endif
    } actions: {
      #if os(iOS)
      Button { dismiss() } label: { Text("settings_done").frame(maxWidth: .infinity) }
        .iosPrototypeAction().disabled(retrying)
      if (job.state == "failed" || job.state == "waiting") && !retrySubmitted {
        Button(action: performRetry) { Text(LocalizedStringKey(retrying ? "apple_retry_running" : "retry_task")).frame(maxWidth: .infinity) }
          .iosPrototypeAction(primary: true).disabled(retrying).accessibilityIdentifier("transfer.detail.retry")
      }
      #else

      Button("settings_done") { dismiss() }.duckSecondaryAction().disabled(retrying)
      if (job.state == "failed" || job.state == "waiting") && !retrySubmitted {
        Button(LocalizedStringKey(retrying ? "apple_retry_running" : "retry_task")) {
          Task {
            guard !retrying else { return }
            retrying = true; retryFailed = false
            let accepted = await retry()
            retrying = false; retrySubmitted = accepted; retryFailed = !accepted
          }
        }.duckPrimaryAction().disabled(retrying)
          .accessibilityIdentifier("transfer.detail.retry")
      }
      #endif
    }
  }
  #if os(macOS)
  private func macField(_ title: LocalizedStringKey, value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(title).font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary).frame(width: 130, alignment: .leading)
      Text(value).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() }
  }
  private func macTimeline(_ title: LocalizedStringKey, detail: String, time: String,
    state: TransferDetailFacts.NodeState, last: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 14, weight: .semibold))
      Text(detail).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Text(time).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }.padding(.leading, 22).padding(.bottom, last ? 0 : 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .topLeading) { timelineMarker(state: state, last: last) }
      .accessibilityElement(children: .combine)
  }
  #endif
  private func performRetry() {
    Task {
      guard !retrying else { return }
      retrying = true; retryFailed = false
      let accepted = await retry()
      retrying = false; retrySubmitted = accepted; retryFailed = !accepted
    }
  }
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  @ScaledMetric(relativeTo: .headline) private var headingSize = 19
  private var iosDetails: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(job.asset.resources.first?.filename ?? "").iosPrototypeText(size: headingSize, weight: .semibold, lineHeight: 1.4)
        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      DuckStatusBadge(text: status, symbol: symbol, tone: tone).symbolVariant(.none)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
        detailField("design_file_type", value: NSLocalizedString("library_filter_" + (job.asset.metadata?["burst_group_ref"] == nil ? job.asset.kind : "burst"), comment: ""))
        detailField("design_capture_time", value: job.asset.metadata?["created_at_ms"].flatMap(Double.init).map {
          Date(timeIntervalSince1970: $0 / 1000).formatted(date: .abbreviated, time: .shortened)
        } ?? NSLocalizedString("task_order_unknown", comment: ""))
        detailField("apple_transfer_detail_receiver", value: targetName)
        detailField("design_file_size", value: ByteCountFormatter.string(fromByteCount: Int64(job.totalBytes), countStyle: .file))
      }
      VStack(alignment: .leading, spacing: 0) {
        timeline(facts.receiptConfirmed ? "apple_transfer_receipt_verified" : "apple_transfer_stage_originals",
          detail: facts.receiptConfirmed ? NSLocalizedString("design_original_retained", comment: "") : status,
          time: receiptTime, state: facts.originalNode)
        timeline("apple_transfer_stage_gallery", detail: galleryDescription,
          time: NSLocalizedString("apple_transfer_gallery_time_unknown", comment: ""), state: facts.galleryNode)
        timeline("Google Photos", detail: NSLocalizedString("apple_transfer_cloud_note", comment: ""),
          time: NSLocalizedString("apple_transfer_cloud_unknown", comment: ""), state: .pending, last: true)
      }
      if job.processing == "failed" { DuckNotice(title: "design_retry_on_pixel", tone: .attention) }
      if let error = job.processingError ?? job.errorCode {
        DuckNotice(title: LocalizedStringKey(NSLocalizedString("error_" + error, comment: "")), tone: .failure)
      }
      if retrySubmitted { DuckNotice(title: "apple_retry_submitted", tone: .action) }
    }
  }
  private func detailField(_ title: LocalizedStringKey, value: String) -> some View {
    GridRow(alignment: .top) {
      Text(title).iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary).frame(minWidth: 80, alignment: .leading)
      Text(value).iosPrototypeText(size: bodySize).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
  }
  private func timeline(_ title: LocalizedStringKey, detail: String, time: String,
    state: TransferDetailFacts.NodeState, last: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).iosPrototypeText(size: bodySize, weight: .semibold)
      Text(detail).iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
      Text(time).iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
    }.padding(.leading, 22).padding(.bottom, last ? 0 : 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .topLeading) { timelineMarker(state: state, last: last) }
      .accessibilityElement(children: .combine)
  }
  #endif

}

struct TransferList: View {
  @ObservedObject var model: BackupModel
  @StateObject private var browser = TaskBrowserModel()
  var sourceOptions: [(String,String)] = []
  var showsHeading = true
  @State private var sourceFilter = ""
  @State private var guidePresented = false
  @State private var visibleJobID: String?
  @State private var filter: String
  @AppStorage("transferSortChoicesV2") private var savedOrders = "{}"
  @Environment(\.dynamicTypeSize) private var textSize
  private var ordering: TransferOrdering {
    get { (try? JSONDecoder().decode([String: TransferOrdering].self, from: Data(savedOrders.utf8)))?[filter] ?? .recommended(filter) }
    nonmutating set {
      var values = (try? JSONDecoder().decode([String: TransferOrdering].self, from: Data(savedOrders.utf8))) ?? [:]
      values[filter] = newValue
      if let data = try? JSONEncoder().encode(values) { savedOrders = String(decoding: data, as: UTF8.self) }
    }
  }
  init(model: BackupModel, filter: String = "all", sourceOptions: [(String,String)] = [], showsHeading: Bool = true) {
    self.model = model
    self.sourceOptions = sourceOptions
    self.showsHeading = showsHeading
    _filter = State(initialValue: TransferUserCategories.initial(filter))
  }
  private var queryID: String {
    "\(sourceFilter)|\(filter)|\(ordering.sort)|\(ordering.descending)|\(model.queueRevision)|\(model.pairing?.receiverID ?? "")"
  }
  var body: some View {
    Group {
      #if os(iOS)
      ScrollView { controls.padding(.bottom, 28) }.scrollPosition(id: $visibleJobID, anchor: .top)
      #else
      controls.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      #endif
    }
    .sheet(isPresented: $guidePresented) { TransferStatusGuide() }
    .task(id: queryID) {
      if filter != "preparing" && filter != "scanned" {
        await refresh()
      }
    }
  }
  private var sourceInline: Bool {
    #if os(iOS)
    true
    #else
    false
    #endif
  }
  private var contentSpacing: CGFloat {
    #if os(iOS)
    8
    #else
    14
    #endif
  }
  private var sourcePage: Bool { filter == "preparing" || filter == "scanned" }
  private var controls: some View {
    VStack(alignment: .leading, spacing: contentSpacing) {
      #if os(iOS)
      if showsHeading || sourcePage {
        Text(LocalizedStringKey(sourcePage ? filter == "scanned" ? "task_title_scanned" : "state_preparing" : "transfer_tasks"))
          .font(.headline).accessibilityIdentifier("transfers.title")
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { compactCount; Spacer(minLength: 8); compactSort; compactGuide }
        VStack(alignment: .leading, spacing: 8) { compactCount; HStack(spacing: 8) { compactSort; Spacer(); compactGuide } }
      }
      #else
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          if showsHeading || sourcePage {
            Text(LocalizedStringKey(sourcePage ? filter == "scanned" ? "task_title_scanned" : "state_preparing" : "transfer_tasks"))
              .font(.headline).accessibilityIdentifier("transfers.title")
          }
          Text(String(format: NSLocalizedString("task_status_count", comment: ""), (sourceFilter.isEmpty || sourcePage) ? model.transferCount(for: filter) : (browser.summary?.count(for: filter) ?? 0)))
            .font(.callout).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("transfers.count")
        }
        Spacer(minLength: 8)
        Button("design_status_guide") { guidePresented = true }
          .buttonStyle(.plain).foregroundStyle(DuckColors.action).frame(minHeight: 44)
          .accessibilityIdentifier("transfers.guide")
      }
      #endif
      if !sourcePage {
        if textSize.isAccessibilitySize { commonFilters.pickerStyle(.menu) }
        else { commonFilters.pickerStyle(.segmented) }
      }
      if !sourceOptions.isEmpty, !sourcePage {
        HStack {
          Text("task_source_filter").font(.callout).foregroundStyle(.secondary)
          Spacer()
          Picker("task_source_filter", selection: $sourceFilter) {
            Text("task_source_all").tag("")
            ForEach(sourceOptions, id: \.0) { Text($0.1).tag($0.0) }
          }.labelsHidden().pickerStyle(.menu).fixedSize()
        }
      }
      #if !os(iOS)
      TransferSortControl(ordering: Binding(get: { ordering }, set: { ordering = $0 }), filter: filter)
      #endif
      if sourcePage {
        SourceBrowser(model: model, history: filter == "scanned", descending: ordering.descending, sort: ordering.sort, inline: sourceInline)
      } else {
        if browser.hasMore { Text(String(format: NSLocalizedString("task_loaded_count", comment: ""), browser.items.count)).font(.caption).foregroundStyle(.secondary) }
        taskRows
      }
    }.frame(maxWidth: .infinity, alignment: .topLeading)
  }
  #if os(iOS)
  private var compactCount: some View {
    Text(String(format: NSLocalizedString("task_status_count", comment: ""), (sourceFilter.isEmpty || sourcePage) ? model.transferCount(for: filter) : (browser.summary?.count(for: filter) ?? 0)))
      .font(.caption).foregroundStyle(DuckColors.textSecondary).monospacedDigit().accessibilityIdentifier("transfers.count")
  }
  private var compactSort: some View {
    TransferSortControl(ordering: Binding(get: { ordering }, set: { ordering = $0 }), filter: filter)
      .font(.subheadline).buttonStyle(.plain).foregroundStyle(DuckColors.action).frame(minHeight: 44)
  }
  private var compactGuide: some View {
    Button { guidePresented = true } label: {
      HStack(spacing: 4) { Text("design_status_guide"); Image(systemName: "chevron.right").font(.caption) }
    }.font(.subheadline).buttonStyle(.plain).foregroundStyle(DuckColors.action)
      .frame(minHeight: 44).accessibilityIdentifier("transfers.guide")
  }
  #endif
  @ViewBuilder private var taskRows: some View {
    #if os(iOS)
    rowStack
    #else
    ScrollView { rowStack }
    #endif
  }
  private var rowStack: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      if browser.loading && browser.items.isEmpty && !browser.hasSnapshot {
        #if os(iOS)
        ProgressView("mac_fidelity_tasks_loading").frame(maxWidth: .infinity).padding(.top, 20)
        #else
        ProgressView().frame(maxWidth: .infinity).padding(.top, 36)
        #endif
      } else if browser.failed {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 12) {
          DuckNotice(title: "tasks_load_failed", tone: .failure)
          Button("retry_task") { Task { await refresh() } }.iosPrototypeAction()
        }.frame(maxWidth: .infinity)
        #else
        VStack(spacing: 12) {
          Text("tasks_load_failed").foregroundStyle(.secondary)
          Button("retry_task") { Task { await refresh() } }
        }.frame(maxWidth: .infinity).padding(.top, 36)
        #endif
      } else if browser.items.isEmpty {
        #if os(iOS)
        DuckNotice(title: "tasks_empty_filtered")
        #else
        ContentUnavailableView("tasks_empty_filtered", systemImage: "line.3.horizontal.decrease.circle")
          .frame(maxWidth: .infinity).padding(.top, 36)
        #endif
      }
      ForEach(browser.items) { item in
        BackupTaskRow(item: item, model: model, activityLabel: ordering.sort == "activity" ? "apple_transfer_activity_time" : nil)
        Divider()
      }
      if browser.hasMore {
        Button("load_more_tasks") { Task { await browser.loadMore() } }
          #if os(iOS)
            .iosPrototypeAction().padding(.vertical, 20)
          #else
            .padding(.vertical, 20)
          #endif
      }
    }.scrollTargetLayout().allowsHitTesting(!browser.loading)
  }
  private var commonFilters: some View {
    Picker("task_filter", selection: $filter) {
      Text("design_filter_all").tag("all")
      Text("design_filter_active").tag("active")
      Text("design_filter_attention").tag("attention")
      Text("design_filter_saved").tag("saved")
    }.accessibilityIdentifier("transfers.common_filter")
  }
  private func refresh() async {
    let receiver = model.pairing?.receiverID
    await browser.refresh(filter: filter, receiver: receiver, descending: ordering.descending, sort: ordering.sort, sourceFilter: sourceFilter.isEmpty ? nil : sourceFilter)
    guard sourceFilter.isEmpty, !Task.isCancelled, receiver == model.pairing?.receiverID,
      !browser.failed, let summary = browser.summary else { return }
    model.summary = summary
  }
}

struct BackupTaskItem: Decodable, Identifiable, Equatable {
  let id: String
  let cursor: Int64
  let sort_value: Int64?
  let job: BackupJob?
  let preparation: SourceBrowserItem?
}

struct BackupTaskRow: View {
  let item: BackupTaskItem
  @ObservedObject var model: BackupModel
  var activityLabel: String? = nil
  var topInset: CGFloat = 12
  @State private var preparationDetails = false
  @State private var retrying = false
  @State private var retryError: String?
  @State private var retrySubmitted = false
  var body: some View {
    Group {
    if let job = item.job {
      TransferRow(job: job, progress: model.transferProgress[job.id], topInset: topInset, activityLabel: activityLabel,
        receiverName: model.receiverDeviceName(for: job)) { await model.retry(job.id) }
    } else if let source = item.preparation {
      Button { preparationDetails = true } label: {
        SourceBrowserRow(item: source, active: model.importingSourceID == source.source, progress: model.exportProgress, topInset: topInset)
      }.buttonStyle(.plain).accessibilityIdentifier("task.preparation." + source.source)
    }
    }.sheet(isPresented: $preparationDetails) {
      if let source = item.preparation {
        DuckSheetLayout(title: "original_preparation_detail", busy: retrying, error: retryError) {
          SourceBrowserRow(item: source, active: model.importingSourceID == source.source, progress: model.exportProgress)
          if model.paused { DuckNotice(title: "backup_paused") }
          if retrySubmitted { DuckNotice(title: "apple_retry_submitted", tone: .action) }
        } actions: {
          Button("settings_done") { preparationDetails = false }.duckSecondaryAction()
          if source.error_code != nil, !retrySubmitted {
            Button("retry_task") { Task {
              guard let receiver = model.pairing?.receiverID else { return }
              retrying = true; retryError = nil
              do {
                _ = try await Bridge.call(["op":"retry_source", "receiver_id":receiver, "source":source.request_id ?? source.source])
                retrySubmitted = true; await model.refresh(includeStorage: false)
              } catch { retryError = error.localizedDescription }
              retrying = false
            } }.duckPrimaryAction().disabled(retrying)
          }
        }
      }
    }
  }
}

/// Filter before pagination so a failure beyond the first page stays discoverable.
@MainActor final class TaskBrowserModel: ObservableObject {
  @Published var items: [BackupTaskItem] = []
  var jobs: [BackupJob] { items.compactMap(\.job) }
  @Published var hasMore = false
  @Published var loading = false
  @Published private(set) var hasSnapshot = false
  @Published var failed = false
  private(set) var summary: SenderSummary?
  private var filter = "all"
  private var sourceFilter: String?
  private var receiver: String?
  private var descending = false
  private var sort = "added"
  private var limit = 200
  private var generation = 0
  private struct Page: Decodable { let items: [BackupTaskItem]; let summary: SenderSummary }
  func loadMore() async {
    guard !loading else { return }
    limit += 200
    await refresh(filter: filter, receiver: receiver, descending: descending, sort: sort, sourceFilter: sourceFilter)
  }
  func refresh(filter: String, receiver: String?, descending: Bool = false, sort: String = "added", sourceFilter: String? = nil) async {
    if self.sourceFilter != sourceFilter || self.filter != filter || self.receiver != receiver || self.descending != descending || self.sort != sort {
      limit = 200
      // Keep the last committed rows during a filter/sort request. Only a
      // receiver change invalidates that snapshot; stale rows are not tappable.
      if self.receiver != receiver { items = []; hasSnapshot = false }
      hasMore = false
      summary = nil
    }
    self.sourceFilter = sourceFilter
    self.descending = descending
    self.sort = sort
    self.filter = filter
    self.receiver = receiver
    generation += 1
    let expected = generation
    guard let receiver else { items = []; hasMore = false; loading = false; return }
    loading = true
    failed = false
    defer { if generation == expected { loading = false } }
    var result: [BackupTaskItem] = []
    var after: Int64 = 0
    var afterValue: Int64?
    do {
      while result.count < limit {
        var query: [String: Any] = ["op": "backup_tasks", "after": after, "descending": descending, "sort": sort]
        if let afterValue { query["after_value"] = afterValue }
        if filter != "all" { query["state"] = filter }
        query["receiver_id"] = receiver
        if let sourceFilter { query["source_filter"] = sourceFilter }
        let data = try await Bridge.call(query)
        let response = try JSONDecoder().decode(Page.self, from: data)
        let page = response.items
        guard expected == generation, !Task.isCancelled else { return }
        self.summary = response.summary
        result.append(contentsOf: page)
        guard page.count == 200, let last = page.last else { break }
        after = last.cursor
        afterValue = last.sort_value
      }
      var summaryQuery: [String: Any] = ["op": "backup_summary", "receiver_id": receiver]
      if let sourceFilter { summaryQuery["source_filter"] = sourceFilter }
      let data = try await Bridge.call(summaryQuery)
      let summary = try JSONDecoder().decode(SenderSummary.self, from: data)
      guard expected == generation, !Task.isCancelled else { return }
      self.summary = summary
      hasSnapshot = true
      if items != result { items = result }
      hasMore = result.count < summary.count(for: filter)
    } catch {
      guard expected == generation, !Task.isCancelled else { return }
      failed = true
    }
  }
}

/// Compact, always-present status; full messages belong in the detail sheet.
struct BackupStatusIndicator: View {
  @ObservedObject var model: BackupModel
  var compactMac = false
  private var controlHeight: CGFloat {
    #if os(macOS)
    32
    #else
    44
    #endif
  }
  var actionTitle: LocalizedStringKey? = nil
  @State private var details = false
  private var title: String {
    if let message = model.message { return message }
    if model.pairing == nil { return NSLocalizedString("receiver_unpaired", comment: "") }
    if !model.ready { return NSLocalizedString("backup_initializing", comment: "") }
    if model.summary.failed + model.summary.publication_failed > 0 {
      return String(format: NSLocalizedString("backup_status_failed_count", comment: ""), model.summary.failed + model.summary.publication_failed)
    }
    if model.waitingForNetwork { return NSLocalizedString("waiting_for_wifi", comment: "") }
    if let reason = model.waitingReason { return NSLocalizedString("error_" + reason, comment: "") }
    if model.summary.received > model.summary.published + model.summary.publication_failed {
      return NSLocalizedString("backup_status_publication_pending", comment: "")
    }
    if model.summary.received > 0 {
      return NSLocalizedString("backup_status_gallery_complete", comment: "")
    }
    return NSLocalizedString(model.paused ? "backup_paused" : "backup_status_ready", comment: "")
  }
  private var status: (key: String, symbol: String, color: Color) {
    if !model.ready { return model.message == nil
      ? ("backup_indicator_starting", "clock", .secondary)
      : ("backup_indicator_attention", "exclamationmark.circle", DuckColors.attention) }
    if model.pairing == nil { return ("backup_indicator_unpaired", "link", .secondary) }
    if model.paused { return ("backup_indicator_paused", "pause.circle", .secondary) }
    if model.message != nil || model.summary.failed + model.summary.publication_failed > 0 {
      return ("backup_indicator_attention", "exclamationmark.circle", DuckColors.attention)
    }
    if model.waitingForNetwork || model.receiverUnavailable {
      return ("backup_indicator_network", "wifi.exclamationmark", DuckColors.attention)
    }
    if model.summary.running > 0 || model.importing {
      return ("backup_indicator_active", "arrow.up.circle", DuckColors.action)
    }
    if model.waitingReason != nil { return ("backup_indicator_retry", "clock", DuckColors.attention) }
    if model.pendingImports > 0 || model.summary.queued > 0 {
      return ("backup_indicator_waiting", "clock", .secondary)
    }
    if model.summary.received > model.summary.published + model.summary.publication_failed {
      return ("backup_indicator_publication_pending", "clock", .secondary)
    }
    if model.summary.received > 0 {
      return ("backup_indicator_gallery_complete", "photo.on.rectangle", DuckColors.action)
    }
    return ("backup_indicator_ready", "checkmark.circle", DuckColors.saved)
  }
  var body: some View {
    Button { details = true } label: {
      if let actionTitle, !compactMac { Text(actionTitle).font(.system(size: 14)).foregroundStyle(DuckColors.action).frame(minHeight: controlHeight) }
      else {
      HStack(spacing: 6) {
        if !compactMac { Image(systemName: status.symbol) }
        Text(actionTitle ?? LocalizedStringKey(status.key)).lineLimit(1)
        if !compactMac { Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)) }
      }.font(compactMac ? .system(size: 12) : .subheadline).foregroundStyle(compactMac ? DuckColors.textSecondary : status.color)
        .padding(.horizontal, compactMac ? 0 : 10).padding(.vertical, compactMac ? 0 : 6)
        .background(status.color.opacity(compactMac ? 0 : 0.09), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: compactMac ? 20 : controlHeight).contentShape(Rectangle())
      }
    }.buttonStyle(.plain).accessibilityIdentifier("backup.status_indicator")
      .accessibilityHint(Text("backup_status_details"))
      .sheet(isPresented: $details) {
        DuckSheetLayout(title: "backup_status_title") {
          #if os(iOS)
          DuckStatusBadge(text: NSLocalizedString(status.key, comment: ""), symbol: status.symbol,
            tone: model.summary.failed + model.summary.publication_failed > 0 ? .failure : .neutral)
          Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow(alignment: .top) {
              Text("apple_status_originals").foregroundStyle(DuckColors.textSecondary)
              Text("\(model.summary.received) / \(model.summary.total)").monospacedDigit()
            }
            GridRow(alignment: .top) {
              Text("apple_status_gallery").foregroundStyle(DuckColors.textSecondary)
              Text("\(model.summary.published) / \(model.summary.received)").monospacedDigit()
            }
          }
          if model.summary.publication_failed > 0 {
            Text(String(format: NSLocalizedString("apple_overview_gallery_failed_count", comment: ""), model.summary.publication_failed))
              .foregroundStyle(DuckColors.failure)
          }
          if let message = model.message {
            Text(message).foregroundStyle(DuckColors.attention).textSelection(.enabled)
          } else { WaitingStatus(model: model) }
          Text("design_gallery_boundary").font(.footnote).foregroundStyle(DuckColors.textSecondary)
          #else
          Label(LocalizedStringKey(status.key), systemImage: status.symbol).foregroundStyle(status.color)
          Text(title).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          Text(String(format: NSLocalizedString("transfer_summary", comment: ""), model.summary.received, model.summary.total))
          Text(String(format: NSLocalizedString("publication_summary", comment: ""), model.summary.published, model.summary.received))
          if model.waitingForNetwork || model.receiverUnavailable { DuckNotice(title: "waiting_for_wifi", tone: .attention, symbol: "wifi.exclamationmark") }
          WaitingStatus(model: model)
          DuckNotice(title: "receipt_explanation", symbol: "cloud")
          #endif
        } actions: {
          #if os(iOS)
          Button { details = false } label: { Text("backup_status_close").frame(maxWidth: .infinity) }.iosPrototypeAction()
          #else
          Button("backup_status_close") { details = false }.duckSecondaryAction()
          #endif
        }
      }
  }
}


/// Pairing has its own messages; unrelated transfer errors never appear here.
struct ReceiverStatusIndicator: View {
  @ObservedObject var model: BackupModel
  var actionTitle: LocalizedStringKey? = nil
  var textOnly = false
  @State private var details = false
  var status: (key: String, symbol: String, color: Color) {
    if model.pairingInProgress { return ("receiver_indicator_pairing", "link", DuckColors.action) }
    if model.pairingError != nil { return ("receiver_indicator_attention", "exclamationmark.circle", DuckColors.attention) }
    if model.pairing == nil { return ("backup_indicator_unpaired", "link", .secondary) }
    if model.checkingConnection { return ("receiver_connection_checking", "arrow.triangle.2.circlepath", .secondary) }
    if model.receiverConnection == .authentication { return ("receiver_indicator_attention", "exclamationmark.circle", .orange) }
    if model.receiverConnection == .unavailable { return ("receiver_connection_unavailable", "exclamationmark.circle", .orange) }
    if model.receiverUnavailable || model.waitingForNetwork {
      return ("receiver_indicator_waiting", "wifi.exclamationmark", DuckColors.attention)
    }
    if model.receiverConnection == .ready {
      return ("receiver_indicator_connected", "wifi", DuckColors.action)
    }
    return ("receiver_indicator_paired", "link", DuckColors.action)
  }
  var body: some View {
    Group {
      #if os(macOS)
        if actionTitle != nil { indicatorButton.duckSecondaryAction().fixedSize() }
        else { indicatorButton.buttonStyle(.plain) }
      #else
        indicatorButton.buttonStyle(.plain)
      #endif
    }.accessibilityIdentifier("receiver.status_indicator")
      .accessibilityHint(Text("backup_status_details"))
      .sheet(isPresented: $details) {
        DuckSheetLayout(title: "receiver_connection_details") {
          #if os(iOS)
          DuckStatusBadge(text: NSLocalizedString(status.key, comment: ""), symbol: status.symbol,
            tone: model.pairingError != nil || model.receiverConnection == .authentication ? .failure : .attention)
          DuckNotice(title: "receiver_local_network", symbol: "wifi")
          if let pairing = model.pairing {
            Text(pairing.endpoint).textSelection(.enabled).foregroundStyle(DuckColors.textSecondary)
            if model.receiverConnection == .authentication { DuckNotice(title: "receiver_connection_authentication", tone: .failure) }
            else if model.receiverConnection == .unavailable { DuckNotice(title: "receiver_connection_unavailable_note", tone: .attention) }
            else if model.receiverUnavailable || model.waitingForNetwork { DuckNotice(title: "receiver_connection_network", tone: .attention) }
            Button { Task { await model.checkConnection() } } label: {
              Text(LocalizedStringKey(model.checkingConnection ? "apple_connection_checking" : "receiver_connection_check")).frame(maxWidth: .infinity)
            }.iosPrototypeAction(primary: true).disabled(model.checkingConnection).accessibilityIdentifier("receiver.check_connection")
          }
          #else
          Label(LocalizedStringKey(status.key), systemImage: status.symbol).foregroundStyle(status.color)
          Text(LocalizedStringKey(model.pairing == nil ? "receiver_pair_instructions" : "receiver_indicator_explanation"))
          if let pairing = model.pairing {
            Text("receiver_address").font(.caption).foregroundStyle(DuckColors.textSecondary)
            Text(pairing.endpoint).font(.callout.monospaced()).textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
            if model.receiverConnection == .authentication { DuckNotice(title: "receiver_connection_authentication", tone: .failure, symbol: "exclamationmark.circle") }
            else if model.receiverConnection == .unavailable { DuckNotice(title: "receiver_connection_unavailable_note", tone: .attention, symbol: "wifi.exclamationmark") }
            else if model.receiverUnavailable || model.waitingForNetwork { DuckNotice(title: "receiver_connection_network", tone: .attention, symbol: "wifi.exclamationmark") }
            if model.checkingConnection { ProgressView("apple_connection_checking") }
          }
          DuckNotice(title: "receiver_local_network")
          #endif
        } actions: {
          #if os(iOS)
          Button { details = false } label: { Text("backup_status_close").frame(maxWidth: .infinity) }.iosPrototypeAction()
          #else
          Button("backup_status_close") { details = false }.duckSecondaryAction()
          if model.pairing != nil {
            Button("receiver_connection_check") { Task { await model.checkConnection() } }
              .duckPrimaryAction().disabled(model.checkingConnection)
              .accessibilityIdentifier("receiver.check_connection")
          }
          #endif
        }
      }
  }
  private var indicatorButton: some View {
    Button { details = true } label: {
      if let actionTitle {
        #if os(macOS)
          Text(actionTitle).font(.system(size: 14)).frame(minHeight: 32)
        #else
          Text(actionTitle).frame(maxWidth: .infinity, minHeight: 32)
        #endif
      }
      else if textOnly { Text(LocalizedStringKey(status.key)).font(.system(size: 14)).foregroundStyle(status.color).frame(minHeight: 44) }
      else {
      HStack(spacing: 6) {
        Image(systemName: status.symbol)
        Text(LocalizedStringKey(status.key)).lineLimit(1)
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
      }.font(.subheadline).foregroundStyle(status.color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(status.color.opacity(0.09), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 44).contentShape(Rectangle())
      }
    }
  }

}


struct TransferOrdering: Codable, Equatable, Hashable {
  var sort: String
  var descending: Bool
  static func recommended(_ filter: String) -> Self {
    switch filter {
    case "waiting": return Self(sort: "retry", descending: false)
    case "running": return Self(sort: "activity", descending: false)
    case "failed": return Self(sort: "activity", descending: true)
    case "all": return Self(sort: "added", descending: true)
    default: return Self(sort: "capture", descending: true)
    }
  }
  static func options(_ filter: String) -> [String] {
    ["capture", "added"] + (["running", "received", "failed"].contains(filter) ? ["activity"] : filter == "waiting" ? ["retry"] : [])
  }
  func basis(_ filter: String) -> String {
    if sort == "activity" { return filter == "received" ? "received" : filter == "failed" ? "failed" : "started" }
    if sort == "added" && filter == "scanned" { return "scan" }
    return sort
  }
}

struct TransferSortChoice: Identifiable, Equatable {
  let sort: String
  let descending: Bool
  let title: String
  var id: String { sort + (descending ? "_latest" : "_earliest") }
  var ordering: TransferOrdering { .init(sort: sort, descending: descending) }
}
enum TransferUserCategories {
  static let keys = ["all", "active", "attention", "saved"]
  static func initial(_ value: String) -> String {
    if keys.contains(value) { return value }
    if value == "preparing" { return "active" }
    if ["running", "queued", "waiting", "paused"].contains(value) { return "active" }
    return value == "failed" ? "attention" : "all"
  }
}
extension TransferOrdering {
  static let directChoices: [TransferSortChoice] = [
    .init(sort: "capture", descending: true, title: "apple_sort_capture_latest"),
    .init(sort: "capture", descending: false, title: "apple_sort_capture_earliest"),
    .init(sort: "added", descending: true, title: "apple_sort_added_latest"),
    .init(sort: "added", descending: false, title: "apple_sort_added_earliest"),
  ]
  var resultTitle: String {
    if sort == "capture" { return descending ? "apple_sort_capture_latest" : "apple_sort_capture_earliest" }
    if sort == "activity" { return descending ? "apple_sort_state_latest" : "apple_sort_state_earliest" }
    if sort == "retry" { return descending ? "apple_sort_retry_latest" : "apple_sort_retry_soonest" }
    return descending ? "apple_sort_added_latest" : "apple_sort_added_earliest"
  }
}
struct TransferSortControl: View {
  @Binding var ordering: TransferOrdering
  let filter: String
  var body: some View {
    Menu {
      Picker("task_order_button", selection: $ordering) {
        ForEach(TransferOrdering.directChoices) { choice in
          Text(LocalizedStringKey(choice.title)).tag(choice.ordering)
            .accessibilityIdentifier("transfers.sort_" + choice.id)
        }
      }.pickerStyle(.inline)
    } label: {
      Label(LocalizedStringKey(ordering.resultTitle), systemImage: "arrow.up.arrow.down")
    }.fixedSize().accessibilityIdentifier("transfers.sort")
  }
}
struct TransferStatusGuide: View {
  @Environment(\.dismiss) private var dismiss
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  #endif
  private let phases: [(String, String)] = [
    ("design_filter_all", "backup_guide_all"),
    ("design_filter_active", "backup_guide_active"),
    ("design_filter_attention", "backup_guide_attention"),
    ("design_filter_saved", "backup_guide_saved"),
  ]

  var body: some View {
    DuckSheetLayout(title: "design_status_guide") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
          VStack(alignment: .leading, spacing: 6) {
            #if os(iOS)
            Text(LocalizedStringKey(phase.0)).iosPrototypeText(size: bodySize, weight: .semibold)
            Text(LocalizedStringKey(phase.1)).iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
            #else
            Text(LocalizedStringKey(phase.0)).font(.system(size: 14, weight: .semibold))
            Text(LocalizedStringKey(phase.1)).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
            #endif
          }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
          if index < phases.count - 1 { Divider() }
        }
      }
    } actions: {
      #if os(iOS)
      Button { dismiss() } label: { Text("settings_done").frame(maxWidth: .infinity) }.iosPrototypeAction()
      #else
      Button("settings_done") { dismiss() }.duckSecondaryAction().keyboardShortcut(.cancelAction)
      #endif
    }
  }
}
