import Foundation

/// The stills each phase requires, from `capture-protocol.md` §4, as data the
/// HUD can show and tick (ADR-0031, design §5).
///
/// A still taken for an item carries the item's id in `stills.jsonl` as the
/// additive `item` field; a still taken with no pick carries nothing and ticks
/// nothing. The list is the protocol's table, not a judgement of the photos:
/// an item is ticked when one still names it, whatever the still shows.
public enum StillsChecklist {
  public struct Item: Equatable, Hashable, Sendable, Identifiable {
    /// Stored as `item`: `panel`, `home-runs`, ...
    public var id: String
    /// Shown on the chip and in the leave check. Short, no commas.
    public var name: String

    public init(id: String, name: String) {
      self.id = id
      self.name = name
    }
  }

  /// Required in every phase, before the phase's own items. Markers are
  /// optional (ADR-0026) so marker stills are not on the list, and the dated
  /// sheet is in the video at the doorway, not a still.
  public static let everyPhase: [Item] = [
    Item(id: "wall", name: "Each wall square-on with the tape")
  ]

  /// The protocol's table, one list per phase. Drywall's and finish's "each
  /// wall" rows are the common wall item and are not repeated.
  public static func items(for phase: CapturePhase) -> [Item] {
    switch phase {
    case .framing:
      return [
        Item(id: "headers", name: "Headers"),
        Item(id: "king-jack-studs", name: "King and jack studs"),
        Item(id: "blocking", name: "Blocking"),
        Item(id: "fire-blocking", name: "Fire blocking"),
        Item(id: "stair-framing", name: "Stair framing"),
        Item(id: "top-plates", name: "Top plates"),
        Item(id: "anchor-bolts", name: "Anchor bolts"),
        Item(id: "hold-downs", name: "Hold-downs"),
        Item(id: "odd-stud-spacing", name: "Odd stud spacing"),
      ]
    case .electrical:
      return [
        Item(id: "boxes", name: "Every box with its cable count"),
        Item(id: "panel", name: "Panel with the cover off"),
        Item(id: "home-runs", name: "Home-run routes"),
        Item(id: "nail-plates", name: "Nail plates"),
        Item(id: "low-voltage", name: "Low-voltage runs"),
        Item(id: "smoke-co", name: "Smoke and CO locations"),
        Item(id: "exterior-penetrations", name: "Exterior penetrations"),
      ]
    case .plumbing:
      return [
        Item(id: "supply", name: "Supply runs and manifold"),
        Item(id: "drains-vents", name: "Drains and vents"),
        Item(id: "cleanouts", name: "Cleanouts"),
        Item(id: "shutoffs", name: "Shutoffs"),
        Item(id: "water-heater", name: "Water heater connections"),
        Item(id: "hose-bibs", name: "Hose bibs"),
        Item(id: "tub-shower-valves", name: "Tub and shower valves"),
        Item(id: "gas", name: "Gas line with every fitting and shutoff"),
      ]
    case .hvac:
      return [
        Item(id: "ducts", name: "Duct trunks and branches"),
        Item(id: "boots", name: "Register and return boots"),
        Item(id: "line-sets", name: "Line sets"),
        Item(id: "condensate", name: "Condensate"),
        Item(id: "flues", name: "Flues"),
        Item(id: "erv-hrv", name: "ERV or HRV ducts"),
        Item(id: "thermostat-wires", name: "Thermostat wires"),
        Item(id: "dampers", name: "Dampers"),
      ]
    case .insulation:
      return [
        Item(id: "bays", name: "Each bay after insulation"),
        Item(id: "vapour-barrier", name: "Vapour barrier seams"),
        Item(id: "sealed-penetrations", name: "Sealed penetrations"),
        Item(id: "hidden-blocking", name: "Blocking hidden behind batts"),
      ]
    case .drywall:
      return [
        Item(id: "screw-lines", name: "Screw lines"),
        Item(id: "access-panels", name: "Access panels"),
        Item(id: "repairs", name: "Repairs"),
      ]
    case .finish:
      return [
        Item(id: "outlets-switches", name: "Every outlet and switch"),
        Item(id: "fixtures-registers", name: "Every fixture and register"),
        Item(id: "flooring-seams", name: "Flooring seams"),
      ]
    case .other:
      return []
    }
  }

  /// The list for a pass: the common items, then each phase's in the order
  /// given, an item two phases share listed once.
  public static func items(for phases: [CapturePhase]) -> [Item] {
    var out = everyPhase
    var seen = Set(out.map(\.id))
    for phase in phases {
      for item in items(for: phase) where !seen.contains(item.id) {
        out.append(item)
        seen.insert(item.id)
      }
    }
    return out
  }

  /// Every item of every phase, for naming an id read back from a file.
  public static let all: [Item] = items(for: CapturePhase.allCases)

  public static func name(for id: String) -> String {
    all.first { $0.id == id }?.name ?? id
  }

  /// What a pass's stills have ticked and what they have not.
  public struct Progress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    public var missing: [Item]

    public var complete: Bool { missing.isEmpty }
  }

  /// `taken` is the `item` of every still written so far; nil and unknown
  /// ids tick nothing.
  public static func progress(items: [Item], taken: [String?]) -> Progress {
    let ticked = Set(taken.compactMap { $0 })
    let missing = items.filter { !ticked.contains($0.id) }
    return Progress(done: items.count - missing.count, total: items.count, missing: missing)
  }
}
