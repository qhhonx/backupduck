import Foundation
import Network

enum ReceiverConnection: Equatable {
  case unknown, ready, network, authentication, unavailable
  static func failure(_ error: Error) -> Self {
    guard let failure = error as? Bridge.Failure else { return .unavailable }
    return failure.code == "authentication" ? .authentication
      : failure.code == "network" ? .network : .unavailable
  }
}

/// Preparation requires an allowed network and a response from the pinned peer.
/// Wi-Fi alone does not establish that the receiver is on the current network.
@MainActor final class ReceiverAvailability {
  private let monitor: NWPathMonitor?
  private let changed: () -> Void
  private let probe: (Pairing) async -> ReceiverConnection
  private var allowed = false
  private var generation = 0
  private var route = ""
  private var result = ReceiverConnection.unknown
  private var expires = Date.distantPast
  private var pending: Task<ReceiverConnection, Never>?
  private(set) var started = false

  init(monitorNetwork: Bool = true, changed: @escaping () -> Void = {},
    probe: ((Pairing) async -> Bool)? = nil,
    diagnose: ((Pairing) async -> ReceiverConnection)? = nil) {
    self.changed = changed
    self.probe = diagnose ?? { pairing in
      if let probe { return await probe(pairing) ? .ready : .network }
      do {
        _ = try await Bridge.call(["op": "check_pairing",
          "pairing": JSONSerialization.jsonObject(with: JSONEncoder().encode(pairing))])
        return .ready
      } catch { return .failure(error) }
    }
    monitor = monitorNetwork ? NWPathMonitor() : nil
    monitor?.pathUpdateHandler = { [weak self] path in
      let interfaces: [NWInterface.InterfaceType] = [.wifi, .wiredEthernet, .cellular]
        .filter { path.usesInterfaceType($0) }
      Task { @MainActor in
        self?.networkChanged(satisfied: path.status == .satisfied, interfaces: interfaces)
      }
    }
  }
  func start() {
    guard !started else { return }
    started = true
    monitor?.start(queue: DispatchQueue(label: "app.backupduck.network"))
  }
  deinit { monitor?.cancel() }

  func networkChanged(satisfied: Bool, interfaces: [NWInterface.InterfaceType]) {
    // NWPath can report Wi-Fi and cellular together. A local interface permits
    // the pinned receiver probe; the upload session still forbids cellular.
    networkChanged(allowed: satisfied
      && (interfaces.contains(.wifi) || interfaces.contains(.wiredEthernet)))
  }

  func networkChanged(allowed: Bool) {
    self.allowed = allowed
    generation += 1
    result = .unknown; expires = .distantPast
    pending?.cancel(); pending = nil
    changed()
  }

  func check(_ pairing: Pairing) async -> Bool {
    await diagnose(pairing) == .ready
  }

  func diagnose(_ pairing: Pairing, force: Bool = false) async -> ReceiverConnection {
    guard allowed else { return .network }
    let key = pairing.receiverID + pairing.endpoint + pairing.certificate + pairing.token
    if key != route || force {
      route = key; generation += 1; expires = .distantPast
      pending?.cancel(); pending = nil
    }
    if Date() < expires { return result }
    let version = generation
    let task: Task<ReceiverConnection, Never>
    if let pending { task = pending } else {
      task = Task { await probe(pairing) }
      pending = task
    }
    let reachable = await task.value
    guard version == generation, allowed, route == key else { return .unknown }
    pending = nil; result = reachable
    expires = Date().addingTimeInterval(reachable == .ready ? 3 : 10)
    return reachable
  }
}
