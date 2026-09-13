import Foundation

/// Namespace for the pure-Swift core.
///
/// Everything testable lives in this package so Linux CI can cover it; the ARKit
/// layer in the app target stays thin. Only Foundation is used here — no simd,
/// no ARKit, no UIKit.
public enum CadastreCore {
  /// Version of the core package, kept in step with the pipeline package.
  public static let version = "0.1.0"

  /// Version of the on-disk session format this core reads and writes.
  ///
  /// The format is the contract between the app and the pipeline; see
  /// `docs/session-format.md`. Additive optional fields keep version 1.
  public static let sessionFormatVersion = 1
}
