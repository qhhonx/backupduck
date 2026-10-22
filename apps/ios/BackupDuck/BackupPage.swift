import SwiftUI

/// The overview presents confirmed local results; source controls and the queue
/// retain their separate workflows, rather than being hidden in a generic menu.
struct IOSBackupPage: View {
  @ObservedObject var model: BackupModel
  @State private var transfers = false
  @State private var pairing = false
  @ScaledMetric(relativeTo: .title2) private var heroSize = 26
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .headline) private var sectionSize = 19
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        IOSPrototypeHeader("nav_backup")
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if model.pairing == nil {
            DuckSurface {
              VStack(alignment: .leading, spacing: 16) {
                DuckBrandMark(size: 76)
                Text("design_backup_title").iosPrototypeText(size: heroSize, weight: .semibold, lineHeight: 1.3)
                  .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Text("backup_pair_first").iosPrototypeText(size: bodySize)
                  .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(DuckColors.textSecondary)
                if !model.ready { BackupStatusIndicator(model: model) }
                Button { pairing = true } label: {
                  Text("pair_receiver").frame(maxWidth: .infinity)
                }.iosPrototypeAction(primary: true)
                  .accessibilityIdentifier("backup.pair")
              }
            }
          } else if !model.ready {
            DuckNotice(title: "backup_initializing")
            if let error = model.message { DuckNotice(title: LocalizedStringKey(error), tone: .attention) }
          } else {
            DuckBackupProgress(model: model, showTransfers: { transfers = true })
          }
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("backup_settings").iosPrototypeText(size: sectionSize, weight: .semibold, lineHeight: 1.4)
              Spacer(minLength: 8)
              NavigationLink { IOSBackupPreferences(model: model) } label: {
                HStack(spacing: 4) {
                  Text("backup_more_settings")
                  Image(systemName: "chevron.right").font(.caption)
                }.foregroundStyle(DuckColors.action).frame(minHeight: 44)
              }.buttonStyle(.plain).accessibilityIdentifier("backup.manage_source")
            }
            IOSPreferenceGroup {
              IOSPreferenceRow(title: "auto_backup_new") {
                Toggle("auto_backup_new", isOn: Binding(get: { model.autoBackup }, set: { enabled in Task { await model.setAutoBackup(enabled) } }))
                  .labelsHidden().disabled(!model.ready || model.pairing == nil || model.changingAutoBackup)
                  .accessibilityIdentifier("backup.auto_backup")
              }
              if let error = model.autoBackupError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).padding(16) }
            }
          }
          if model.pairing == nil {
            VStack(alignment: .leading, spacing: 12) {
              Text("design_recent_transfers").iosPrototypeText(size: sectionSize, weight: .semibold, lineHeight: 1.4)
              DuckNotice(title: "tasks_empty")
            }
          } else { DuckRecentTransfers(model: model, showTransfers: { transfers = true }) }

        }.iosPrototypePageBody()
      }
      }.background(DuckRole.background).foregroundStyle(DuckColors.text).toolbar(.hidden, for: .navigationBar).symbolVariant(.none)
      .navigationDestination(isPresented: $transfers) {
        IOSPrototypeDestination(title: "transfer_tasks") {
          TransferList(model: model, showsHeading: false).frame(maxWidth: 600).padding(.horizontal, 16).padding(.top, 4).frame(maxWidth: .infinity)
        }
      }
      .sheet(isPresented: $pairing) { IOSPairingFlow(model: model) }

    }
  }
}
