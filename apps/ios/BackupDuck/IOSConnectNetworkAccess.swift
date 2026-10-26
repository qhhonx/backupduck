import Network
import UIKit

/// A bounded, user-initiated preflight. No payload or credentials are sent here;
/// Rust still authenticates the QR certificate and receiver before saving trust.
/// iOS owns permission dialogs. In particular, there is no public WLAN-approval
/// query; an unavailable path must not be presented as a proven denial.
@MainActor final class IOSConnectNetworkAccess {
  private var path: NWPath?
  private var connectionState = NWConnection.State.setup
  private var connectionPath: NWPath?

  func prepare(_ pairing: Pairing) async throws {
    guard BackupEnvironment.usesNetwork else { return }
    // A preflight belongs to one decoded scan; stale callbacks cannot leak into retry.
    path = nil; connectionPath = nil; connectionState = .setup
    guard let url = URLComponents(string: pairing.endpoint), url.scheme == "https",
      let host = url.host, !host.isEmpty,
      let port = NWEndpoint.Port(rawValue: UInt16(exactly: url.port ?? 443) ?? 0),
      port.rawValue != 0 else { throw Bridge.Failure(code: "invalid_input") }

    // Start only general path observation first. Do not browse Bonjour, create
    // a background session or open a local socket while wireless access waits.
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in self?.path = path }
    }
    monitor.start(queue: DispatchQueue(label: "app.backupduck.connect.path"))
    defer { monitor.cancel() }
    try await waitForLocalPath()

    let parameters = NWParameters.tcp
    parameters.prohibitedInterfaceTypes = [.cellular]
    let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      Task { @MainActor in
        self?.connectionState = state
        self?.connectionPath = connection?.currentPath
      }
    }
    connection.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in self?.connectionPath = path }
    }
    connection.start(queue: DispatchQueue(label: "app.backupduck.connect.peer"))
    defer { connection.cancel() }
    try await waitForPeer()
  }

  private func waitForLocalPath() async throws {
    var elapsed = 0.0
    var settled = 0.0
    while elapsed < 10 {
      try await Task.sleep(for: .milliseconds(100))
      guard UIApplication.shared.applicationState == .active else { settled = 0; continue }
      elapsed += 0.1
      if let path, path.status == .satisfied,
        path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
        settled += 0.1
        if settled >= 0.5 { return }
      } else { settled = 0 }
    }
    if path?.unsatisfiedReason == .wifiDenied || path?.unsatisfiedReason == .cellularDenied {
      throw ConnectAccessFailure.wireless
    }
    throw ConnectAccessFailure.unavailable
  }

  private func waitForPeer() async throws {
    var elapsed = 0.0
    while elapsed < 10 {
      try await Task.sleep(for: .milliseconds(100))
      // Time spent answering a system permission dialog is not a peer timeout.
      guard UIApplication.shared.applicationState == .active else { continue }
      elapsed += 0.1
      if case .ready = connectionState { return }
      if case .failed = connectionState, elapsed >= 1 { break }
    }
    switch connectionPath?.unsatisfiedReason {
    case .localNetworkDenied: throw ConnectAccessFailure.localNetwork
    case .wifiDenied, .cellularDenied: throw ConnectAccessFailure.wireless
    default: throw ConnectAccessFailure.unavailable
    }
  }
}
