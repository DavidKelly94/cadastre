import Foundation

/// Constants the app shares, kept out of the views so a number appears once.
///
/// Anything here that the pipeline also relies on comes from `CadastreCore` or
/// from `docs/session-format.md`, not from a literal typed twice.
enum AppConfig {
  static let productName = "Cadastre"

  /// The depth map ARKit delivers, and what the format records.
  static let depthWidth = 256
  static let depthHeight = 192

  /// Colour frames are stored exactly as ARKit delivers them: landscape, unrotated.
  static let colourWidth = 1920
  static let colourHeight = 1440

  static let defaultJPEGQuality = 0.85
  static let markerPhysicalWidth = 0.20

  /// At most one still per second, and one high-resolution capture in flight.
  static let minimumStillInterval: TimeInterval = 1.0

  /// Writer queue depth. Two lets encoding overlap the next frame's copy without
  /// letting a backlog grow: past this a keyframe is dropped and counted, which
  /// is honest, where queueing without limit would spend memory and then die.
  static let writerQueueDepth = 2

  /// JSONL is flushed every this many lines, and on close.
  static let flushEveryLines = 50
}
