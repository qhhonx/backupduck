import SwiftUI

/// Overview uses verified gallery results; full queue stays on its own page.
struct IOSBackupPage: View {
  @ObservedObject var model: BackupModel
  @State private var picker = false
  @State private var transfers = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if model.pairing == nil {
            DuckSurface {
              VStack(alignment: .leading, spacing: 16) {
                DuckBrandMark()
                BackupStatusIndicator(model: model)
                Text("design_backup_title").font(.title2.weight(.semibold))
                Text("backup_pair_first").foregroundStyle(DuckColors.textSecondary)
                NavigationLink { IOSReceiverPage(model: model) } label: {
                  Label("pair_receiver", systemImage: "qrcode.viewfinder")
                }.buttonStyle(.borderedProminent)
              }
            }
          } else {
            if let peer = model.peerDevice { Text(peer.name).font(.headline) }
            DuckBackupProgress(model: model, showTransfers: { transfers = true })
          }
          Text("design_backup_sources").font(.headline)
          DuckSurface { DuckLibrarySource(model: model) }
          DuckRecentTransfers(model: model, showTransfers: { transfers = true })
          DisclosureGroup("design_advanced_tasks") {
            VStack(spacing: 0) {
              ForEach(["preparing", "running", "queued", "waiting", "paused", "failed", "received", "scanned"], id: \.self) { state in
                NavigationLink {
                  TransferList(model: model, filter: state).padding(20)
                    .navigationTitle(LocalizedStringKey(state == "scanned" ? "task_title_scanned" : "state_" + state))
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                  HStack {
                    Label(LocalizedStringKey(state == "scanned" ? "task_title_scanned" : "state_" + state), systemImage: taskSymbol(state))
                    Spacer()
                    Text(model.transferCount(for: state).formatted()).monospacedDigit()
                  }.padding(.vertical, 12)
                }.accessibilityIdentifier("backup.filter.\(state)")
                Divider()
              }
            }
          }
        }.padding(20)
      }.background(DuckColors.canvas)
      .navigationTitle("nav_backup")
      .navigationDestination(isPresented: $transfers) {
        TransferList(model: model).padding(.horizontal, 20).padding(.top, 12)
          .navigationTitle("transfer_tasks").navigationBarTitleDisplayMode(.inline)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { Task { if await model.authorizePhotos() { picker = true } } } label: {
            Label("choose_photos", systemImage: "plus")
          }.disabled(model.pairing == nil || model.importing)
        }
      }
      .sheet(isPresented: $picker) {
        LibraryPicker { identifiers in picker = false; Task { await model.importAssets(identifiers) } }
      }
    }
  }
}
