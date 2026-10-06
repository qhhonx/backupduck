import SwiftUI

struct MacBackupPage: View {
  @ObservedObject var model: BackupModel
  var pair: () -> Void
  var library: () -> Void
  var sources: () -> Void
  var showTransfers: (String) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text("backup_overview_heading").font(.title.weight(.semibold))
            Text("design_backup_title").font(.callout).foregroundStyle(DuckColors.textSecondary)
          }
          Spacer()
          Button("backup_choose_library", action: library).buttonStyle(.bordered)
        }
        if model.pairing == nil {
          DuckSurface {
            VStack(alignment: .leading, spacing: 16) {
              DuckBrandMark()
              Text("mac_pair_first").font(.headline)
              Button("pair_receiver_desktop", action: pair).buttonStyle(.borderedProminent)
            }
          }
        } else {
          HStack(alignment: .top, spacing: 20) {
            DuckBackupProgress(model: model, showTransfers: { showTransfers("all") })
            DuckSurface {
              VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "iphone").font(.title).foregroundStyle(DuckColors.action)
                Text(model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: "")).font(.headline)
                ReceiverStatusIndicator(model: model)
                Text(model.pairing?.endpoint ?? "").font(.caption).foregroundStyle(DuckColors.textSecondary).lineLimit(2)
                Button("pair_another_receiver", action: pair).font(.callout)
              }
            }.frame(width: 240)
          }
        }
        Text("design_backup_sources").font(.headline)
        DuckSurface {
          VStack(alignment: .leading, spacing: 16) {
            DuckLibrarySource(model: model)
            Divider()
            HStack(spacing: 12) {
              Image(systemName: "folder").foregroundStyle(DuckColors.action)
                .frame(width: 36, height: 36).background(DuckColors.actionBackground, in: RoundedRectangle(cornerRadius: 10))
              Text("mac_nav_sources").font(.headline)
              Spacer()
              Button("design_manage_folders", action: sources)
            }
          }
        }
        DuckRecentTransfers(model: model, showTransfers: { showTransfers("all") })
        DisclosureGroup("design_advanced_tasks") {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(["preparing", "running", "queued", "waiting", "paused", "failed", "received", "scanned"], id: \.self) { state in
              Button { showTransfers(state) } label: {
                HStack {
                  Text(LocalizedStringKey(state == "scanned" ? "task_title_scanned" : "state_" + state)).foregroundStyle(DuckColors.textSecondary)
                  Spacer()
                  Text(model.transferCount(for: state).formatted()).monospacedDigit()
                }.padding(12).background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 10))
              }.buttonStyle(.plain).accessibilityIdentifier("backup.filter.\(state)")
            }
          }.padding(.top, 12)
        }
      }.frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).padding(28)
    }.background(DuckColors.canvas)
  }
}
