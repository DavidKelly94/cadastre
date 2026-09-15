import VividHomeCore

extension CapturePhase {
  /// The owner-facing name. The raw value is the contract value and goes in the
  /// manifest; this is only ever shown.
  var displayName: String {
    switch self {
    case .framing: return "Framing"
    case .electrical: return "Electrical"
    case .plumbing: return "Plumbing"
    case .hvac: return "HVAC"
    case .insulation: return "Insulation"
    case .drywall: return "Drywall"
    case .finish: return "Finish"
    case .other: return "Other"
    }
  }

  /// A short form for the HUD strip, where the room and trades share one line.
  var shortName: String {
    switch self {
    case .electrical: return "Elec"
    case .insulation: return "Insul"
    default: return displayName
    }
  }
}
