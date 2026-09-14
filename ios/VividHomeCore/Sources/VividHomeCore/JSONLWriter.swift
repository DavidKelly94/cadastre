import Foundation

/// Appends JSON Lines to a file, one record per line.
///
/// Every `.jsonl` file in a session is written through this: open once at session
/// start, append as records arrive, close at stop. Records are encoded with sorted
/// keys so two runs of the same capture produce byte-identical lines, which makes
/// the sample session in `samples/` a usable fixture.
///
/// Not thread-safe, and deliberately so: each file has one writer owned by the
/// capture session, and adding a lock here would hide a caller doing something
/// unintended.
public final class JSONLWriter {
  public enum Failure: Error, Equatable {
    case couldNotCreateFile(path: String)
  }

  private let handle: FileHandle
  private let encoder: JSONEncoder
  private var isOpen = true

  /// The encoder every session file uses.
  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    // Sorted for reproducibility; slashes unescaped so the relative paths in a
    // record read as rgb/000123.jpg rather than rgb\/000123.jpg.
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  /// Opens `url` for appending, creating it if it does not exist.
  public init(url: URL, encoder: JSONEncoder = JSONLWriter.makeEncoder()) throws {
    let manager = FileManager.default
    if !manager.fileExists(atPath: url.path) {
      guard manager.createFile(atPath: url.path, contents: nil) else {
        throw Failure.couldNotCreateFile(path: url.path)
      }
    }
    self.handle = try FileHandle(forWritingTo: url)
    self.encoder = encoder
    try self.handle.seekToEnd()
  }

  deinit {
    try? handle.close()
  }

  /// Encodes `value` and appends it as one line.
  ///
  /// A JSON encoder without pretty printing never emits a raw newline — control
  /// characters in strings are escaped — so one record is always one line.
  public func append<T: Encodable>(_ value: T) throws {
    var data = try encoder.encode(value)
    data.append(0x0A)
    try handle.write(contentsOf: data)
  }

  /// Appends several records in order.
  public func append<T: Encodable>(contentsOf values: [T]) throws {
    for value in values {
      try append(value)
    }
  }

  /// Flushes to disk.
  ///
  /// Called at checkpoints rather than per record: a session that dies mid-capture
  /// is recoverable from the files present, and syncing every keyframe would cost
  /// more than it saves.
  public func synchronize() throws {
    try handle.synchronize()
  }

  /// Flushes and closes. Further appends will throw.
  public func close() throws {
    guard isOpen else { return }
    isOpen = false
    try handle.synchronize()
    try handle.close()
  }
}
