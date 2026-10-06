import SwiftUI

/// Shared visual primitives; business state stays in the model.
struct DuckSurface<Content: View>: View {
  @ViewBuilder var content: () -> Content
  var body: some View {
    content().padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 16))
      .overlay { RoundedRectangle(cornerRadius: 16).stroke(DuckColors.border, lineWidth: 1) }
  }
}

enum DuckTone {
  case action, saved, attention, failure, neutral
  var color: Color {
    switch self {
    case .action: return DuckColors.action
    case .saved: return DuckColors.saved
    case .attention: return DuckColors.attention
    case .failure: return DuckColors.failure
    case .neutral: return DuckColors.textSecondary
    }
  }
  var background: Color {
    switch self {
    case .action: return DuckColors.actionBackground
    case .saved: return DuckColors.savedBackground
    case .attention: return DuckColors.attentionBackground
    case .failure: return DuckColors.failureBackground
    case .neutral: return DuckColors.subtle
    }
  }
}

struct DuckStatusBadge: View {
  let text: String
  let symbol: String
  let tone: DuckTone
  var body: some View {
    Label(text, systemImage: symbol).font(.caption.weight(.medium))
      .foregroundStyle(tone.color).padding(.horizontal, 8).padding(.vertical, 5)
      .background(tone.background, in: RoundedRectangle(cornerRadius: 7))
  }
}

struct DuckBrandMark: View {
  var size: CGFloat = 64
  private var image: Image? {
    guard let url = Bundle.main.url(forResource: "DuckBrand", withExtension: "png") else { return nil }
    #if os(macOS)
      guard let value = NSImage(contentsOf: url) else { return nil }
      return Image(nsImage: value)
    #else
      guard let value = UIImage(contentsOfFile: url.path) else { return nil }
      return Image(uiImage: value)
    #endif
  }
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.3).fill(DuckColors.brandAccentBackground)
      if let image { image.resizable().scaledToFit().padding(size * 0.15) }
      else { Image(systemName: "bird.fill").font(.system(size: size * 0.5)).foregroundStyle(DuckColors.brandAccent) }
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}

struct DuckBackupProgress: View {
  @ObservedObject var model: BackupModel
  var showTransfers: () -> Void
  private var fraction: Double {
    model.summary.total > 0 ? Double(model.summary.published) / Double(model.summary.total) : 0
  }
  var body: some View {
    DuckSurface {
      VStack(alignment: .leading, spacing: 16) {
        BackupStatusIndicator(model: model)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(model.summary.published.formatted()).font(.system(size: 42, weight: .semibold)).monospacedDigit()
          Text(String(format: NSLocalizedString("design_saved_of", comment: ""), model.summary.total))
            .font(.callout).foregroundStyle(DuckColors.textSecondary)
        }
        ProgressView(value: fraction).tint(DuckColors.action)
          .accessibilityLabel(Text("state_published"))
        HStack {
          Text(String(format: NSLocalizedString("design_in_progress", comment: ""),
            model.summary.running + model.summary.queued + model.summary.waiting + model.summary.paused,
            model.summary.failed + model.summary.publication_failed))
            .font(.caption).foregroundStyle(DuckColors.textSecondary)
          Spacer(minLength: 0)
        }
        HStack {
          Button { Task { await model.setPaused(!model.paused) } } label: {
            Label(model.paused ? "resume_backup" : "pause_backup", systemImage: model.paused ? "play" : "pause")
          }.buttonStyle(.borderedProminent).disabled(!model.ready || model.pairing == nil)
          Button("backup_all_tasks", action: showTransfers).buttonStyle(.bordered)
        }
        Text("receipt_explanation").font(.caption).foregroundStyle(DuckColors.textSecondary)
      }
    }
  }
}

struct DuckLibrarySource: View {
  @ObservedObject var model: BackupModel
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "photo.on.rectangle").foregroundStyle(DuckColors.action)
        .frame(width: 36, height: 36).background(DuckColors.actionBackground, in: RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 4) {
        Text("source_system_library").font(.headline)
        Text("design_source_media").font(.caption).foregroundStyle(DuckColors.textSecondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 4) {
        Text("auto_backup_new").font(.caption).foregroundStyle(DuckColors.textSecondary)
        Toggle("auto_backup_new", isOn: Binding(get: { model.autoBackup }, set: { enabled in
        Task { await model.setAutoBackup(enabled) }
      })).labelsHidden().disabled(!model.ready || model.changingAutoBackup || model.pairing == nil)
        .accessibilityLabel(Text("auto_backup_new"))
      }
    }
  }
}

struct DuckRecentTransfers: View {
  @ObservedObject var model: BackupModel
  @StateObject private var browser = TaskBrowserModel()
  var showTransfers: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("design_recent_transfers").font(.headline)
        Spacer()
        Button("backup_all_tasks", action: showTransfers).font(.callout)
      }
      if browser.failed {
        Text("tasks_load_failed").foregroundStyle(DuckColors.failure)
        Button("retry_task") { Task { await refresh() } }
      } else if browser.loading && browser.jobs.isEmpty {
        ProgressView().frame(maxWidth: .infinity)
      } else if browser.jobs.isEmpty {
        Text("tasks_empty").font(.callout).foregroundStyle(DuckColors.textSecondary)
      } else {
        ForEach(Array(browser.jobs.prefix(3))) { job in
          TransferRow(job: job, progress: model.transferProgress[job.id]) { Task { await model.retry(job.id) } }
          Divider()
        }
      }
    }.task(id: "\(model.queueRevision)|\(model.pairing?.receiverID ?? "")") { await refresh() }
  }
  private func refresh() async {
    await browser.refresh(filter: "all", receiver: model.pairing?.receiverID, descending: true, sort: "added")
  }
}
