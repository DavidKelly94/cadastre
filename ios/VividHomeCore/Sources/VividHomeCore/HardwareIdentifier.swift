/// Reading the hardware identifier the kernel reports, out of a fixed-width buffer.
///
/// `UIDevice.current.model` returns "iPhone" for every iPhone ever made. Section
/// 4 of `session-format.md` asks for something else — its example is
/// "iPhone16,1" — and the difference matters for this record in particular:
/// LiDAR sensor generation varies by model and depth quality with it, so a
/// reader years from now needs to know which phone produced the depth they are
/// looking at. Raw sessions are immutable (rule 6), so a session written with
/// "iPhone" is permanently missing that, the same way the absolute-timestamp
/// sessions were permanently missing their origin.
///
/// The identifier comes from `uname`, whose `machine` field is a fixed-size C
/// buffer holding a NUL-terminated string. The decoding lives here rather than
/// at the call site because the buffer is the part that can be silently wrong:
/// read the whole width and you get the identifier with trailing NULs attached,
/// which compares unequal to the identifier and looks fine in a log.
public enum HardwareIdentifier {

  /// The string in a fixed-width, NUL-terminated buffer, or nil when it holds
  /// no text.
  ///
  /// Nil rather than "" so the caller has to decide what to do about it; the
  /// app falls back to the generic model name, which is wrong but is at least
  /// not an empty field in the contract.
  public static func decode<Bytes: Sequence>(_ bytes: Bytes) -> String?
  where Bytes.Element == UInt8 {
    let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    return text.isEmpty ? nil : text
  }
}
