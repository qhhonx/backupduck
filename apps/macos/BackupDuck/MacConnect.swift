import SwiftUI

/// Connecting a Pixel from the Mac (design/mac-connect.md). The Mac shows the
/// code and the Pixel scans it: the code is the subject, numbered steps say what to do on the other device using
/// the Pixel's own words, and the sheet continues by itself once the Pixel has
/// scanned. The pairing session is the existing `DesktopPairingModel`.
struct MacConnectSheet: View {
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @StateObject private var exchange = DesktopPairingModel()
  @State private var connected = false

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if connected { success } else { code }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(28)
      HStack {
        Spacer()
        if connected {
          Button("records_done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        } else {
          Button("cancel") { exchange.stop(); dismiss() }.buttonStyle(.bordered).keyboardShortcut(.cancelAction).disabled(model.pairingInProgress)
          if exchange.error != nil {
            Button("mac_connect_try_again") { start() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.pairingInProgress)
          }
        }
      }
      .padding(16)
    }
    .frame(width: 620, height: 460)
    .onAppear { start() }
    .onDisappear { exchange.stop() }
  }

  private func start() {
    exchange.begin(model: model) { withAnimation(.smooth(duration: 0.25)) { connected = true } }
  }

  private var code: some View {
    HStack(alignment: .center, spacing: 32) {
      ZStack {
        // The white quiet zone exists only for a code; errors and progress sit on the page surface.
        if exchange.image != nil, exchange.error == nil {
          RoundedRectangle(cornerRadius: 16).fill(.white)  // design-exception: QR codes need a white quiet zone in both appearances
        } else {
          RoundedRectangle(cornerRadius: 16).fill(DuckRole.groupedSurface)
        }
        if let image = exchange.image, !model.pairingInProgress {
          Image(nsImage: image).interpolation(.none).resizable().scaledToFit().padding(14)
            .accessibilityLabel(Text("mac_connect_code"))
        } else if exchange.error == nil {
          ProgressView().controlSize(.large)
        }
      }
      .frame(width: 220, height: 220)
      .overlay {
        if let error = exchange.error {
          VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.title).foregroundStyle(DuckRole.attention)
            Text(LocalizedStringKey(error)).font(.callout).multilineTextAlignment(.center).foregroundStyle(.primary)
          }.padding(16)
        }
      }
      VStack(alignment: .leading, spacing: 16) {
        Text("mac_connect_title").font(.title2.weight(.semibold))
        VStack(alignment: .leading, spacing: 12) {
          step(1, "mac_connect_step_open")
          step(2, "mac_connect_step_switch")
          step(3, "mac_connect_step_scan")
        }
        Text(model.pairingInProgress ? "mac_connect_connecting" : "mac_connect_note")
          .font(.callout).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(number.formatted()).font(.callout.weight(.semibold)).foregroundStyle(DuckRole.accent)
        .frame(width: 18, alignment: .trailing)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
  }

  private var success: some View {
    VStack(spacing: 14) {
      DuckIllustration(pose: .pairing, size: 140)
      Text(String(format: NSLocalizedString("onboarding_connected_title", comment: ""), model.peerDevice?.name ?? "Pixel"))
        .font(.title2.weight(.semibold))
      Text("onboarding_connected_body").foregroundStyle(.secondary)
    }
    .transition(.opacity)
  }
}
