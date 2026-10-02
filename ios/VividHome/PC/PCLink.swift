import Combine
import Foundation
import Network
import VividHomeCore

/// The PC that holds the rendering (ADR-0028), on the home network or, since
/// ADR-0029, on the owner's tailnet.
///
/// Finds it over Bonjour, or takes an address the owner typed; fetches
/// `/index.json` to say what it holds and how old that is; turns a project
/// level into the URL of its rendered page; and keeps the pairing code that
/// lets `SessionUploader` send captures. Nothing else here writes to the PC.
///
/// Not `@MainActor`, like the app's other observable objects: it is created in
/// a view's property initialiser. Every published value is still set on the
/// main queue — the browser and the resolving connections are started on it,
/// and `test()` is isolated so its awaits resume there.
final class PCLink: ObservableObject {
  /// What the owner typed, or the address of a discovered PC they picked.
  @Published var addressText: String {
    didSet { UserDefaults.standard.set(addressText, forKey: Self.addressKey) }
  }
  /// The store's pairing code (ADR-0029), from the Keychain; empty when none.
  /// Read nothing needs it; sending a capture does.
  @Published var pairingCode: String {
    didSet { PairingCode.write(pairingCode) }
  }
  @Published private(set) var discovered: [Discovered] = []
  @Published private(set) var index: ServerIndex?
  @Published private(set) var checkedAt: Date?
  @Published private(set) var problem: String?
  /// What the PC said about the pairing code on the last test: nil when it
  /// was accepted or there was none to try.
  @Published private(set) var pairingProblem: String?
  @Published private(set) var testing = false

  struct Discovered: Identifiable, Equatable {
    var id: String { name }
    var name: String
    /// Nil until the service name has been resolved to a host and port.
    var url: URL?
  }

  /// Must match `SERVICE_TYPE` in the pipeline's `serve.py` and
  /// `NSBonjourServices` in `ios/project.yml`; change all three or none.
  static let serviceType = "_vividhome._tcp"
  private static let addressKey = "pc.address"

  private var browser: NWBrowser?

  init() {
    addressText = UserDefaults.standard.string(forKey: Self.addressKey) ?? ""
    pairingCode = PairingCode.read() ?? ""
  }

  var baseURL: URL? { PCAddress.url(from: addressText) }
  var isConfigured: Bool { baseURL != nil }
  var hasPairingCode: Bool {
    !pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  /// An address and a code: what a send needs before it can start.
  var canSend: Bool { isConfigured && hasPairingCode }

  // MARK: - Discovery

  func startBrowsing() {
    guard browser == nil else { return }
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
    // Started on the main queue, so the handler already runs there.
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      self?.update(results)
    }
    browser.start(queue: .main)
    self.browser = browser
  }

  func stopBrowsing() {
    browser?.cancel()
    browser = nil
  }

  private func update(_ results: Set<NWBrowser.Result>) {
    var found: [Discovered] = []
    for result in results {
      guard case .service(let name, _, _, _) = result.endpoint else { continue }
      let known = discovered.first { $0.name == name }
      found.append(Discovered(name: name, url: known?.url))
      if known?.url == nil {
        resolve(result.endpoint, name: name)
      }
    }
    discovered = found.sorted { $0.name < $1.name }
  }

  /// Bonjour hands over a service name; a URL needs a host and a port.
  /// Connecting once resolves it, then the connection is dropped.
  private func resolve(_ endpoint: NWEndpoint, name: String) {
    let connection = NWConnection(to: endpoint, using: .tcp)
    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready:
        var url: URL?
        if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
          url = URL(string: "http://\(Self.text(for: host)):\(port.rawValue)")
        }
        connection.cancel()
        self?.resolved(name: name, url: url)
      case .failed, .cancelled:
        connection.cancel()
      default:
        break
      }
    }
    connection.start(queue: .main)
  }

  private static func text(for host: NWEndpoint.Host) -> String {
    switch host {
    case .ipv4(let address):
      return "\(address)"
    case .ipv6(let address):
      return "[\(address)]"
    case .name(let name, _):
      return name
    @unknown default:
      return "\(host)"
    }
  }

  private func resolved(name: String, url: URL?) {
    guard let position = discovered.firstIndex(where: { $0.name == name }) else { return }
    discovered[position].url = url
  }

  func use(_ item: Discovered) {
    guard let url = item.url else { return }
    addressText = url.absoluteString
  }

  // MARK: - The index

  /// Fetch `/index.json` and keep what came back, or say why nothing did.
  @MainActor
  func test() async {
    guard let base = baseURL else {
      problem = "Type the PC's address, or pick one that was found."
      return
    }
    testing = true
    defer { testing = false }
    problem = nil
    do {
      var request = URLRequest(url: base.appendingPathComponent("index.json"))
      request.timeoutInterval = 6
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard status == 200 else {
        throw Problem.status(status)
      }
      index = try JSONDecoder().decode(ServerIndex.self, from: data)
      checkedAt = Date()
      if hasPairingCode {
        pairingProblem = await Self.checkPairing(base: base, code: pairingCode)
      } else {
        pairingProblem = nil
      }
    } catch {
      index = nil
      problem = Self.describe(error)
    }
  }

  /// Ask the PC whether it takes this pairing code, by listing an inbox entry
  /// that cannot exist: a well-formed id (section 1) nothing ever records
  /// under. 200 means the code is accepted; 401 and 403 say what is wrong.
  private static func checkPairing(base: URL, code: String) async -> String? {
    guard let url = URL(string: base.absoluteString + "/upload/00000101-000000_probe_probe_aaaaaa")
    else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 6
    request.setValue(
      "Bearer \(code.trimmingCharacters(in: .whitespacesAndNewlines))",
      forHTTPHeaderField: "Authorization")
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
      case 200:
        return nil
      case 401:
        return "The PC refused this pairing code. `vividhome serve --lan` prints the right one."
      case 403:
        return "The PC has no pairing code yet. Run `vividhome serve --lan` there once; "
          + "it prints the code."
      case let status:
        return "The PC answered the pairing check with HTTP \(status)."
      }
    } catch {
      return "The pairing check did not get an answer: \(error.localizedDescription)"
    }
  }

  private enum Problem: Error {
    case status(Int)
  }

  private static func describe(_ error: Error) -> String {
    if case Problem.status(let code) = error {
      return "The address answered, but not as VividHome (HTTP \(code)). "
        + "Is `vividhome serve --lan` what is running there?"
    }
    if error is DecodingError {
      return "The PC answered with something this build does not understand. "
        + "Update one side or the other."
    }
    guard let code = (error as? URLError)?.code else {
      return error.localizedDescription
    }
    switch code {
    case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
      return "Nothing answered at that address. Is the PC on and running "
        + "`vividhome serve --lan`? On the home Wi-Fi, a guest network that isolates "
        + "devices looks the same as a PC that is off; on a tailnet name, Tailscale "
        + "has to be connected on both the phone and the PC."
    case .notConnectedToInternet:
      return "This phone is not on a network."
    default:
      return error.localizedDescription
    }
  }

  /// Fetch again only when the last answer is older than `maxAge` seconds, or
  /// there is none. The project screen calls this on every appearance, and
  /// with the PC off a fetch is a six-second timeout each time.
  @MainActor
  func refreshIfStale(maxAge: TimeInterval = 60) async {
    guard isConfigured else { return }
    if let checkedAt, index != nil, Date().timeIntervalSince(checkedAt) < maxAge { return }
    await test()
  }

  /// The rendered page for a level, if the PC has one.
  func inspectURL(project: String, level: String) -> URL? {
    guard let base = baseURL, let page = index?.inspectPage(project: project, level: level)
    else { return nil }
    return base.appendingPathComponent(page)
  }
}
