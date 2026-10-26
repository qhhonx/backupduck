import Foundation
import Network

enum ReceiverConnection: Equatable {
  case unknown, ready, network, localNetworkDenied, authentication, unavailable
  static func failure(_ error: Error) -> Self {
    guard let failure = error as? Bridge.Failure else { return .unavailable }
    return failure.code == "authentication" ? .authentication
      : failure.code == "network" ? .network : .unavailable
  }
}

/// UI evidence is independent of the executor's immediate preparation gate.
/// A route notification is never a failed probe. Success clears at once.
struct ReceiverReachability {
  private(set) var connection = ReceiverConnection.unknown
  private var failure: ReceiverConnection?
  private var firstFailure: Date?
  private var failures = 0
  mutating func observe(_ result: ReceiverConnection, at now: Date) {
    guard result != .unknown else { return }
    if result == .ready {
      connection = .ready; failure = nil; firstFailure = nil; failures = 0
    } else {
      failures += 1
      if firstFailure == nil { firstFailure = now }
      failure = result
      advance(to: now)
    }
  }
  mutating func advance(to now: Date) {
    if let failure, let firstFailure, failures >= 2 || now.timeIntervalSince(firstFailure) >= 10 {
      connection = failure
    }
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
  private let now: () -> Date
  private var reachability = ReceiverReachability()
  var visibleConnection: ReceiverConnection {
    reachability.advance(to: now())
    return reachability.connection
  }
  private(set) var started = false

  init(monitorNetwork: Bool = true, now: @escaping () -> Date = Date.init, changed: @escaping () -> Void = {},
    probe: ((Pairing) async -> Bool)? = nil,
    diagnose: ((Pairing) async -> ReceiverConnection)? = nil,
    localNetworkDenied: @escaping (Pairing) async -> Bool = { await LocalNetworkDenialCheck.check($0) }) {
    self.changed = changed
    self.now = now
    let diagnose = diagnose ?? { pairing in
      if let probe { return await probe(pairing) ? .ready : .network }
      do {
        _ = try await Bridge.call(["op": "check_pairing",
          "pairing": JSONSerialization.jsonObject(with: JSONEncoder().encode(pairing))])
        return .ready
      } catch { return .failure(error) }
    }
    self.probe = { pairing in
      let result = await diagnose(pairing)
      guard result == .network, !Task.isCancelled else { return result }
      return await localNetworkDenied(pairing) ? .localNetworkDenied : .network
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
    expires = .distantPast
    pending?.cancel(); pending = nil
    changed()
  }

  func check(_ pairing: Pairing) async -> Bool {
    await diagnose(pairing) == .ready
  }

  func diagnose(_ pairing: Pairing, force: Bool = false) async -> ReceiverConnection {
    // A disallowed path stops preparation without becoming failed-probe evidence.
    guard allowed else { return .network }
    let key = pairing.receiverID + pairing.endpoint + pairing.certificate + pairing.token
    if key != route || force {
      if key != route { reachability = ReceiverReachability() }
      route = key; generation += 1; expires = .distantPast
      pending?.cancel(); pending = nil
    }
    if now() < expires { return result }
    let version = generation
    let task: Task<ReceiverConnection, Never>
    if let pending { task = pending } else {
      task = Task { await probe(pairing) }
      pending = task
    }
    let reachable = await task.value
    guard version == generation, allowed, route == key else { return .unknown }
    // Concurrent callers share one observation, not two consecutive failures.
    if pending != nil { reachability.observe(reachable, at: now()) }
    pending = nil; result = reachable
    expires = now().addingTimeInterval(3)
    return reachable
  }
}

/// A payload-free TCP attempt distinguishes an explicit OS denial from an
/// ordinary unreachable peer. Every completion and cancellation stays serialized.
private final class LocalNetworkDenialCheck: @unchecked Sendable {
  private let queue = DispatchQueue(label: "app.backupduck.network.denial")
  private var connection: NWConnection?
  private var deadline: DispatchWorkItem?
  private var continuation: CheckedContinuation<Bool, Never>?
  private var finished = false

  static func check(_ pairing: Pairing) async -> Bool {
    guard BackupEnvironment.usesNetwork else { return false }
    guard let endpoint = URLComponents(string: pairing.endpoint), endpoint.scheme == "https",
      let host = endpoint.host, !host.isEmpty,
      let rawPort = UInt16(exactly: endpoint.port ?? 443), rawPort != 0,
      let port = NWEndpoint.Port(rawValue: rawPort) else { return false }
    let check = LocalNetworkDenialCheck()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        check.queue.async {
          guard !check.finished else { continuation.resume(returning: false); return }
          check.continuation = continuation
          let parameters = NWParameters.tcp
          parameters.prohibitedInterfaceTypes = [.cellular]
          let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
          check.connection = connection
          connection.stateUpdateHandler = { [weak check, weak connection] state in
            guard let check else { return }
            switch state {
            case .waiting, .failed:
              check.finish(connection?.currentPath?.unsatisfiedReason == .localNetworkDenied)
            case .ready, .cancelled: check.finish(false)
            default: break
            }
          }
          let deadline = DispatchWorkItem { check.finish(false) }
          check.deadline = deadline
          check.queue.asyncAfter(deadline: .now() + 2, execute: deadline)
          connection.start(queue: check.queue)
        }
      }
    } onCancel: {
      check.queue.async { check.finish(false) }
    }
  }

  private func finish(_ denied: Bool) {
    guard !finished else { return }
    finished = true
    deadline?.cancel(); deadline = nil
    connection?.stateUpdateHandler = nil
    connection?.cancel(); connection = nil
    continuation?.resume(returning: denied); continuation = nil
  }
}
