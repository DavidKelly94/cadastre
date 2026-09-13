import Foundation

/// What the app should do about the current disk and thermal state.
public enum HealthVerdict: Equatable, Sendable {
  /// Keep recording.
  case ok
  /// Keep recording but tell the owner, with a reason to show.
  case warn(String)
  /// Stop the session now, with a reason to show and to write to the log.
  case stop(String)
}

/// Disk and thermal limits for a recording session.
///
/// The disk numbers come from `docs/session-format.md` §10: refuse to start below
/// 2 GB free, stop at 500 MB free. They are decimal gigabytes, matching how iOS
/// reports free space to the owner, so the number the app refuses at is the number
/// they see in Settings.
///
/// The margin between the two is deliberate. A five-minute room is 300–800 MB, so
/// starting with 2 GB leaves room for the session plus the stills, while the
/// 500 MB stop threshold leaves enough space to finish writing the mesh and
/// rewrite the manifest after the last keyframe.
public enum HealthPolicy {
  public static let minimumFreeBytesToStart = 2_000_000_000
  public static let minimumFreeBytesToStop = 500_000_000

  /// Whether a new session may begin.
  public static func canStart(freeBytes: Int) -> Bool {
    freeBytes >= minimumFreeBytesToStart
  }

  /// Why a session may not begin, or nil when it may.
  public static func startRefusal(freeBytes: Int) -> String? {
    guard !canStart(freeBytes: freeBytes) else { return nil }
    return
      "Not enough free space to start: \(gigabytes(freeBytes)) GB free, "
      + "\(gigabytes(minimumFreeBytesToStart)) GB needed."
  }

  /// What to do partway through a session.
  ///
  /// Disk is checked before heat because running out of space corrupts the
  /// session being written, while heat only degrades the next frames.
  public static func verdict(freeBytes: Int, thermal: ThermalState) -> HealthVerdict {
    if freeBytes <= minimumFreeBytesToStop {
      return .stop("Stopping: only \(megabytes(freeBytes)) MB of space left.")
    }
    switch thermal {
    case .critical:
      return .stop("Stopping: the phone is too hot to keep recording.")
    case .serious:
      return .warn("The phone is hot. Capture continues, but consider a break.")
    case .nominal, .fair:
      break
    }
    if freeBytes <= minimumFreeBytesToStart {
      return .warn("Space is low: \(gigabytes(freeBytes)) GB left.")
    }
    return .ok
  }

  private static func gigabytes(_ bytes: Int) -> String {
    String(format: "%.1f", Double(bytes) / 1_000_000_000)
  }

  private static func megabytes(_ bytes: Int) -> String {
    String(format: "%.0f", Double(bytes) / 1_000_000)
  }
}
