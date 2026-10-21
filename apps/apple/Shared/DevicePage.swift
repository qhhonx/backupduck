import SwiftUI

/// The device page behind Settings › Devices (design/navigation.md, D3;
/// interaction.md I2 detail). It answers "which Pixel do my photos go to, and is
/// it there?": the Pixel, whether it can be reached, and the two facts the
/// backup knows about it. Google Photos' state is never claimed (P3).
struct DevicePage: View {
  @ObservedObject var model: BackupModel
  /// Starts connecting a Pixel with the platform's own connect flow.
  var connect: () -> Void

  var body: some View {
    Form {
      if let pairing = model.pairing {
        Section {
          VStack(spacing: DuckSpacing.xSmall) {
            Image(systemName: "smartphone").font(.largeTitle).foregroundStyle(.primary)
              .frame(width: 72, height: 72)
              .background(DuckRole.background, in: RoundedRectangle(cornerRadius: DuckRadius.card, style: .continuous))
              .accessibilityHidden(true)
            Text(verbatim: model.peerDevice?.name ?? "Pixel").font(.title3.weight(.semibold))
            DuckPill(title: reachability, dot: reachable ? DuckRole.saved : DuckRole.attention)
          }
          .frame(maxWidth: .infinity).padding(.vertical, DuckSpacing.xSmall)
          .accessibilityElement(children: .combine)
        }
        Section {
          LabeledContent("device_received", value: model.summary.count(for: "received").formatted())
          LabeledContent("device_saved", value: model.summary.count(for: "saved").formatted())
        } footer: {
          Text("device_google_note")
        }
        Section {
          Button("device_switch", action: connect)
        }
        .id(pairing.receiverID)
      } else {
        Section {
          DuckEmptyState(pose: .pairing, title: "hub_not_paired", note: "hub_not_paired_note") {
            Button("hub_connect", action: connect).duckPrimaryButton()
          }
        }
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("settings_devices")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .task { await model.refreshDeviceStatus() }
  }

  private var reachable: Bool { model.receiverConnection == .ready }

  /// The device's own reading, never a guess: connected now, or when it was last seen.
  private var reachability: Text {
    if reachable { return Text("device_connected_now") }
    if let seen = model.deviceSnapshot?.peers.first(where: { $0.key == model.pairing?.receiverID })?.last_seen, seen > 0 {
      let date = Date(timeIntervalSince1970: TimeInterval(seen))
      return Text(String(format: NSLocalizedString("device_last_seen", comment: ""), date.formatted(.relative(presentation: .named))))
    }
    return Text("device_unreachable")
  }
}
