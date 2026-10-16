import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

var senderDeviceType: String {
  #if os(macOS)
    return "Mac"
  #else
    return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
  #endif
}

struct DeviceProfile: Codable, Equatable {
  let id: String
  let name: String
}
struct DeviceSnapshot: Decodable {
  struct Peer: Decodable {
    let key: String
    let profile: DeviceProfile
    let last_seen: Int64
  }
  let device: DeviceProfile
  let peers: [Peer]
}
extension BackupModel {
  /// Names are optional display metadata, scoped to the job's stored target id.
  /// A different current pairing must not relabel an older task.
  func receiverDeviceName(for job: BackupJob) -> String? {
    guard let id = job.receiverID, !id.isEmpty,
      let name = deviceSnapshot?.peers.first(where: { $0.key == id })?.profile.name,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return name
  }
  var peerDevice: DeviceProfile? {
    guard let pairing else { return nil }
    return deviceSnapshot?.peers.first { $0.key == pairing.receiverID }?.profile
  }
  func refreshDeviceStatus() async {
    do {
      let data = try await Bridge.call(["op": "device_status",
        "root": root.appendingPathComponent("queue").path,
        "language": Locale.current.language.languageCode?.identifier ?? "en"])
      deviceSnapshot = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
      deviceError = nil
    } catch { deviceError = NSLocalizedString("device_load_failed", comment: "") }
  }
  func renameDevice(_ name: String) async -> Bool {
    guard !savingDevice else { return false }
    savingDevice = true
    deviceError = nil
    defer { savingDevice = false }
    do {
      let data = try await Bridge.call(["op": "device_status",
        "root": root.appendingPathComponent("queue").path,
        "name": name])
      deviceSnapshot = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
      lastDeviceExchange = .distantPast
      Task { await syncDeviceProfile(force: true) }
      return true
    } catch let error as Bridge.Failure where error.code == "invalid_input" {
      deviceError = NSLocalizedString("device_name_invalid", comment: "")
      return false
    } catch {
      deviceError = NSLocalizedString("device_save_failed", comment: "")
      return false
    }
  }
  func syncDeviceProfile(force: Bool = false) async {
    guard ready, let target = pairing, !exchangingDevice,
      force || Date().timeIntervalSince(lastDeviceExchange) >= 60 else { return }
    exchangingDevice = true
    lastDeviceExchange = Date()
    defer { exchangingDevice = false }
    do {
      _ = try await Bridge.call(["op": "exchange_device", "device_type": senderDeviceType,
        "pairing": try JSONSerialization.jsonObject(with: JSONEncoder().encode(target))])
      // The remembered peer is scoped by the receiver's certificate identity.
      await refreshDeviceStatus()
    } catch {
      // A nickname is optional display metadata. Keep the offline name and do
      // not change queue state or replace a meaningful transfer error.
    }
  }
}

struct DeviceIdentitySettings: View {
  @ObservedObject var model: BackupModel
  @State private var editing = false
  var body: some View {
    Group {
      if let profile = model.deviceSnapshot?.device {
        LabeledContent("device_this_device", value: profile.name)
        Button("device_rename") { editing = true }
          .buttonStyle(.borderless).accessibilityIdentifier("device.rename")
          .sheet(isPresented: $editing) { DeviceNameEditor(model: model, name: profile.name) }
      } else {
        if model.deviceError != nil {
          Text("device_load_failed").foregroundStyle(.secondary)
          Button("retry_task") { Task { await model.refreshDeviceStatus() } }
        } else { ProgressView().controlSize(.small) }
      }
      Text("device_name_note").font(.footnote).foregroundStyle(.secondary)
    }.task { if model.deviceSnapshot == nil { await model.refreshDeviceStatus() } }
  }
}
struct DeviceNameEditor: View {
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @State var name: String
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  #endif
  private var valid: Bool {
    let scalars = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
    return !scalars.isEmpty && scalars.count <= 40 && !scalars.contains {
      CharacterSet.controlCharacters.contains($0) || (0x2028...0x202e).contains($0.value) || (0x2066...0x2069).contains($0.value)
    }
  }
  var body: some View {
    DuckSheetLayout(title: "device_rename", busy: model.savingDevice, error: model.deviceError) {
      #if os(iOS)
      Text("device_name_note").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
      #endif
      VStack(alignment: .leading, spacing: 8) {
        #if os(iOS)
        Text("device_name").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
        #else
        Text("device_name").font(.caption.weight(.medium)).foregroundStyle(DuckColors.textSecondary)
        #endif
        TextField("device_name", text: $name).textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("device.name").disabled(model.savingDevice)
      }
      #if os(macOS)
      DuckNotice(title: "device_name_note")
      #endif
      if !valid { Text("device_name_invalid").font(.callout).foregroundStyle(DuckColors.failure) }
      if model.savingDevice { DuckLoadingState("apple_working") }
    } actions: {
      #if os(iOS)
      Button { dismiss() } label: { Text("device_cancel").frame(maxWidth: .infinity) }
        .iosPrototypeAction().disabled(model.savingDevice)
      Button { Task { if await model.renameDevice(name) { dismiss() } } } label: { Text("device_save").frame(maxWidth: .infinity) }
        .iosPrototypeAction(primary: true).disabled(model.savingDevice || !valid).accessibilityIdentifier("device.name_save")
      #else
      Button("device_cancel") { dismiss() }.duckSecondaryAction().disabled(model.savingDevice)
      Button("device_save") { Task { if await model.renameDevice(name) { dismiss() } } }
        .duckPrimaryAction().disabled(model.savingDevice || !valid).accessibilityIdentifier("device.name_save")
      #endif
    }.onAppear { model.deviceError = nil }
  }
}
