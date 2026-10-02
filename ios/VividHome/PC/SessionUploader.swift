import Combine
import Foundation
import Network
import UIKit
import VividHomeCore

/// Sends captures to the PC's inbox, one file per request (§14.1, ADR-0029).
///
/// The shape follows from the size of a capture: hundreds of megabytes in
/// thousands of files, over whatever network the phone has. So each file is its
/// own request, three at a time; the PC's listing of its inbox says what is
/// already there, and a send that stopped resumes from it; and `done` at the
/// end hands the capture to `ingest`, whose answer is shown under the row.
///
/// Not `@MainActor`, like the app's other observable objects. Every published
/// value is set from the main actor: `send` is isolated to it and the upload
/// tasks hop back to report.
final class SessionUploader: ObservableObject {
  struct Job: Identifiable {
    var id: String { layout.root.lastPathComponent }
    var layout: SessionLayout
    var name: String
    /// The project's `plans/` folder beside the session, sent with it (§13).
    var plans: URL?
  }

  struct Item: Identifiable, Equatable {
    var id: String
    var name: String
    var state: State

    enum State: Equatable {
      case waiting
      case sending
      case skipped(String)
      case ingested(validated: Bool, note: String)
      case failed(String)
    }
  }

  @Published private(set) var items: [Item] = []
  @Published private(set) var running = false
  @Published private(set) var finished = false
  @Published private(set) var sentBytes = 0
  @Published private(set) var totalBytes = 0
  /// Why the whole send stopped, when it did not run to the end.
  @Published private(set) var stoppedBecause: String?

  private let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 6 * 60 * 60
    configuration.httpMaximumConnectionsPerHost = 3
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration)
  }()
  private var task: Task<Void, Never>?

  /// How many files are in flight at once. Three keeps a LAN busy without
  /// opening a connection per file; the server speaks keep-alive.
  static let concurrency = 3

  enum Failure: LocalizedError {
    /// The server answered and said no; the status says how finally.
    case refused(Int, String)
    case badAnswer(String)

    var errorDescription: String? {
      switch self {
      case .refused(let status, let message):
        return "\(message) (HTTP \(status))"
      case .badAnswer(let what):
        return what
      }
    }

    /// A wrong pairing code or an unpaired server fails every capture alike,
    /// so one such answer ends the send; a 409 is about one capture.
    var stopsEverything: Bool {
      if case .refused(let status, _) = self { return status == 401 || status == 403 }
      return false
    }
  }

  // MARK: - Driving

  /// Not isolated, so a button action can call it; the work itself runs on
  /// the main actor inside the task.
  func start(_ jobs: [Job], to base: URL, code: String) {
    guard !running else { return }
    task = Task { @MainActor in
      await self.send(jobs, to: base, code: code)
    }
  }

  func cancel() {
    task?.cancel()
  }

  @MainActor
  private func send(_ jobs: [Job], to base: URL, code: String) async {
    running = true
    finished = false
    stoppedBecause = nil
    sentBytes = 0
    items = jobs.map { Item(id: $0.id, name: $0.name, state: .waiting) }
    UIApplication.shared.isIdleTimerDisabled = true
    defer {
      UIApplication.shared.isIdleTimerDisabled = false
      running = false
      finished = true
    }

    // Everything to send, listed up front so the progress bar has a total.
    var listed: [String: [SessionUpload.File]] = [:]
    for job in jobs {
      let layout = job.layout
      let plans = job.plans
      do {
        listed[job.id] = try await Task.detached {
          try SessionUpload.files(of: layout, plans: plans)
        }.value
      } catch {
        set(job.id, .failed("Could not list the capture's files: \(error.localizedDescription)"))
      }
    }
    totalBytes = listed.values.reduce(0) { $0 + SessionUpload.totalBytes($1) }

    for job in jobs {
      guard let files = listed[job.id] else { continue }
      if Task.isCancelled {
        set(job.id, .skipped("Not sent; stopped."))
        continue
      }
      set(job.id, .sending)
      do {
        try await send(job, files: files, to: base, code: code)
      } catch is CancellationError {
        set(job.id, .failed("Stopped. Sending again picks up where this left off."))
        stoppedBecause = "Stopped."
      } catch let failure as Failure where failure.stopsEverything {
        set(job.id, .failed(failure.localizedDescription))
        stoppedBecause = failure.localizedDescription
      } catch let failure as Failure {
        set(job.id, .failed(failure.localizedDescription))
      } catch {
        // The network went: cellular dropped, Tailscale disconnected, the PC
        // went to sleep. Every later capture would fail the same way.
        set(job.id, .failed(Self.describe(error)))
        stoppedBecause = Self.describe(error)
      }
      if stoppedBecause != nil {
        for other in jobs where other.id != job.id {
          if case .waiting? = state(of: other.id) {
            set(other.id, .skipped("Not sent; the send stopped."))
          }
        }
        break
      }
    }
  }

  @MainActor
  private func send(_ job: Job, files: [SessionUpload.File], to base: URL, code: String) async throws {
    let listing = try await fetchListing(job.id, base: base, code: code)
    if listing.isIngested {
      sentBytes += SessionUpload.totalBytes(files)
      set(job.id, .skipped("Already on the PC."))
      return
    }
    let remaining = SessionUpload.remaining(files, given: listing)
    sentBytes += SessionUpload.totalBytes(files) - SessionUpload.totalBytes(remaining)

    // Three in flight at once; as each lands the next starts, and a thrown
    // error leaves the group, which cancels the rest.
    let sessionID = job.id
    try await withThrowingTaskGroup(of: Int.self) { group in
      var next = remaining.makeIterator()
      var inFlight = 0
      for _ in 0..<Self.concurrency {
        guard let file = next.next() else { break }
        inFlight += 1
        group.addTask {
          try await self.put(file, sessionID: sessionID, base: base, code: code)
          return file.bytes
        }
      }
      while inFlight > 0 {
        let bytes = try await group.next() ?? 0
        inFlight -= 1
        sentBytes += bytes
        if let file = next.next() {
          inFlight += 1
          group.addTask {
            try await self.put(file, sessionID: sessionID, base: base, code: code)
            return file.bytes
          }
        }
      }
    }

    let receipt = try await finish(job.id, base: base, code: code)
    set(job.id, .ingested(validated: receipt.validated, note: receipt.summary))
  }

  @MainActor
  private func set(_ id: String, _ state: Item.State) {
    guard let position = items.firstIndex(where: { $0.id == id }) else { return }
    items[position].state = state
  }

  @MainActor
  private func state(of id: String) -> Item.State? {
    items.first { $0.id == id }?.state
  }

  // MARK: - Requests

  private func request(
    _ method: String, _ path: String, base: URL, code: String, timeout: TimeInterval = 60
  ) throws -> URLRequest {
    guard let url = URL(string: base.absoluteString + path) else {
      throw Failure.badAnswer("The PC's address and \(path) do not make a URL.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = timeout
    request.setValue("Bearer \(code.trimmingCharacters(in: .whitespacesAndNewlines))",
      forHTTPHeaderField: "Authorization")
    return request
  }

  private func fetchListing(_ sessionID: String, base: URL, code: String) async throws
    -> SessionUpload.Listing
  {
    let request = try request("GET", "/upload/\(sessionID)", base: base, code: code)
    let (data, response) = try await session.data(for: request)
    try Self.check(response, data: data, expecting: 200)
    return try Self.decode(SessionUpload.Listing.self, from: data)
  }

  /// One file, with two more tries on a network error; a refusal is final.
  private func put(_ file: SessionUpload.File, sessionID: String, base: URL, code: String)
    async throws
  {
    let request = try request(
      "PUT", "/upload/\(sessionID)/\(file.path)", base: base, code: code, timeout: 120)
    var attempt = 0
    while true {
      try Task.checkCancellation()
      do {
        let (data, response) = try await session.upload(for: request, fromFile: file.url)
        try Self.check(response, data: data, expecting: 201)
        return
      } catch let error as URLError where attempt < 2 && error.code != .cancelled {
        attempt += 1
        try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
      }
    }
  }

  /// `done` runs validate on the PC, which reads every frame; it is given time.
  private func finish(_ sessionID: String, base: URL, code: String) async throws
    -> SessionUpload.Receipt
  {
    var request = try request(
      "POST", "/upload/\(sessionID)/done", base: base, code: code, timeout: 600)
    request.httpBody = Data()
    let (data, response) = try await session.data(for: request)
    try Self.check(response, data: data, expecting: 200)
    return try Self.decode(SessionUpload.Receipt.self, from: data)
  }

  private static func check(_ response: URLResponse, data: Data, expecting: Int) throws {
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status != expecting else { return }
    let message = (try? JSONDecoder().decode(SessionUpload.Refusal.self, from: data))?.error
    switch status {
    case 401:
      throw Failure.refused(status, "The PC refused the pairing code. Check it under PC.")
    case 403:
      throw Failure.refused(
        status,
        message ?? "The PC does not take uploads; run `vividhome serve --lan` there once.")
    case 409:
      throw Failure.refused(status, message ?? "The PC already has this capture.")
    default:
      throw Failure.refused(status, message ?? "The PC answered with HTTP \(status).")
    }
  }

  private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw Failure.badAnswer(
        "The PC answered with something this build does not understand. Update one side or the other.")
    }
  }

  private static func describe(_ error: Error) -> String {
    guard let code = (error as? URLError)?.code else { return error.localizedDescription }
    switch code {
    case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
      return "The PC stopped answering. Is it on, is `vividhome serve --lan` running, "
        + "and is this phone on the home Wi-Fi or connected to the tailnet? "
        + "Sending again picks up where this left off."
    case .notConnectedToInternet:
      return "iOS is not letting this app reach the local network, or the phone is offline. "
        + "Check Settings → Privacy & Security → Local Network. Sending again picks up "
        + "where this left off."
    default:
      return error.localizedDescription
    }
  }

  // MARK: - The network the phone is on

  /// Whether the current path is cellular or a hotspot, which the send sheet
  /// says before gigabytes go over it.
  static func pathIsExpensive() async -> Bool {
    await withCheckedContinuation { continuation in
      let monitor = NWPathMonitor()
      var answered = false
      monitor.pathUpdateHandler = { path in
        guard !answered else { return }
        answered = true
        monitor.cancel()
        continuation.resume(
          returning: path.isExpensive || path.usesInterfaceType(.cellular))
      }
      monitor.start(queue: .main)
    }
  }
}
