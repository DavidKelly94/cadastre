import SwiftUI
import VividHomeCore

/// What a capture needs before it can start: a level, a room and at least one
/// trade. Deliberately small — the designed Project and Room screens will
/// replace it, and until they exist this is what stands between the capture
/// layer and a real session on disk.
struct CaptureSetupView: View {
  @ObservedObject var coordinator: CaptureCoordinator
  @ObservedObject var plans: PlanStore
  /// Owned by ContentView, because the plan screens key on the same level.
  @Binding var levelName: String
  @Binding var roomName: String
  let onAddPlan: () -> Void
  let onShowCoverage: () -> Void
  let onShowSessions: () -> Void

  @State private var typedRoom = ""
  @State private var notes = ""
  /// Defaults to the last set used, which on a site is nearly always the right
  /// answer: trades finish a floor before they move on.
  @AppStorage("lastPhases") private var lastPhases = ""
  @State private var phases: Set<CapturePhase> = []

  /// Sentinel for "not one of the placed rooms". Not a slug, so it can never
  /// collide with a real room name.
  private static let newRoomTag = "\u{0000}new"

  /// The rooms already on this level's plan, which are the ones a capture
  /// should normally be for.
  private var placedRooms: [String] {
    (plans.plans[levelSlug]?.rooms.map(\.room) ?? []).sorted()
  }

  /// The Picker's selection, resolved so it always names a tag the Picker
  /// offers. Without this, arriving with `roomName` still empty — which is the
  /// first run, and every run after a room is placed from the plan screen —
  /// leaves the Picker with no matching tag: a blank row, no text field, and
  /// Start disabled. A binding settles it in both directions rather than an
  /// `onAppear` that does not fire again when a sheet is dismissed.
  private var roomSelection: Binding<String> {
    Binding(
      get: {
        if self.roomName == Self.newRoomTag || self.placedRooms.contains(self.roomName) {
          return self.roomName
        }
        return self.placedRooms.first ?? Self.newRoomTag
      },
      set: { self.roomName = $0 })
  }

  /// What the capture is actually for, whichever way it was chosen.
  private var effectiveRoom: String {
    if placedRooms.isEmpty || roomSelection.wrappedValue == Self.newRoomTag {
      return typedRoom.trimmingCharacters(in: .whitespaces)
    }
    return roomSelection.wrappedValue
  }

  private var roomIsPlaced: Bool {
    guard let slug = SessionID.slug(effectiveRoom), let plan = plans.plans[levelSlug] else {
      return false
    }
    return plan.placement(of: slug) != nil
  }

  private var canStart: Bool {
    !effectiveRoom.isEmpty && !phases.isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Level", text: $levelName)

          // The room slug is the join key between a session and its placement
          // on the plan, so retyping it is not a convenience question: "Bedroom"
          // and "bedroom 2" slugify differently, and the capture then belongs to
          // a room nothing else knows about. Once a room is on the plan it is
          // picked, never typed again.
          if !placedRooms.isEmpty {
            Picker("Room", selection: roomSelection) {
              ForEach(placedRooms, id: \.self) { room in
                Text(room).tag(room)
              }
              Text("Another room…").tag(Self.newRoomTag)
            }
          }

          if placedRooms.isEmpty || roomSelection.wrappedValue == Self.newRoomTag {
            TextField("Room name", text: $typedRoom)
              .textInputAutocapitalization(.words)
          }
        } header: {
          Text("Where")
        } footer: {
          if !placedRooms.isEmpty {
            Text("Rooms come from the plan, so a capture lands on the room it is actually in.")
          }
        }

        Section {
          // Multi-select, because a pass can expose several trades at once
          // (ADR-0022). A single picker would force the owner to throw away
          // everything but one.
          ForEach(CapturePhase.allCases, id: \.self) { phase in
            Button {
              if phases.contains(phase) { phases.remove(phase) } else { phases.insert(phase) }
            } label: {
              HStack {
                Text(phase.displayName)
                Spacer()
                if phases.contains(phase) {
                  Image(systemName: "checkmark").foregroundStyle(.tint)
                }
              }
            }
            .buttonStyle(.plain)
          }
        } header: {
          Text("Trades exposed in this pass")
        } footer: {
          Text("Pick every trade you can see. They can be corrected afterwards.")
        }

        Section {
          if let plan = plans.plans[levelSlug] {
            Button(action: onShowCoverage) {
              HStack {
                Label("Plan for \(levelName)", systemImage: "map")
                Spacer()
                Text(placementSummary(plan))
                  .font(.footnote).foregroundStyle(.secondary)
              }
            }
          } else {
            Button(action: onAddPlan) {
              Label("Add a plan for \(levelName)", systemImage: "map")
            }
          }

          // A room typed here is fine — a hallway may not be labelled on the
          // drawing at all — but it has to end up on the plan, or the capture
          // has nothing to be placed against (ADR-0026).
          if plans.plans[levelSlug] != nil, !effectiveRoom.isEmpty, !roomIsPlaced {
            Button(action: onShowCoverage) {
              Label {
                Text("\(effectiveRoom) is not on the plan yet")
              } icon: {
                Image(systemName: "mappin.slash").foregroundStyle(.orange)
              }
            }
          }
        } header: {
          Text("Plan")
        } footer: {
          // Said here rather than discovered later: a capture without a plan is
          // a valid session that cannot be placed on the record (ADR-0026).
          Text(plans.plans[levelSlug] == nil
            ? "You can record without one, but nothing can be placed on the record until a plan exists for this level."
            : "Tap to see which rooms are captured, and to drag this room to where it actually is.")
        }

        Section("Notes") {
          TextField("Optional", text: $notes, axis: .vertical).lineLimit(1...4)
        }

        Section {
          Button("Start capture") { start() }
            .disabled(!canStart)
        }

        Section {
          Button(action: onShowSessions) {
            Label("Past captures", systemImage: "square.stack.3d.up")
          }
        } footer: {
          Text("Share a capture to the PC any time, not only in the moment after recording it.")
        }
      }
      .navigationTitle("New capture")
      .onAppear(perform: restorePhases)
    }
  }

  private var levelSlug: String { SessionID.slug(levelName) ?? "l1" }

  private func placementSummary(_ plan: PlanFile) -> String {
    let slug = SessionID.slug(effectiveRoom)
    if let slug, plan.placement(of: slug) != nil { return "this room placed" }
    return "\(plan.rooms.count) placed"
  }

  private func restorePhases() {
    phases = Set(lastPhases.split(separator: ",").compactMap { CapturePhase(rawValue: String($0)) })
  }

  private func start() {
    let trimmedRoom = effectiveRoom
    // Hand the chosen room back up, so the plan screens and the session agree
    // on one name.
    roomName = trimmedRoom
    let trimmedLevel = levelName.trimmingCharacters(in: .whitespaces)
    let ordered = CapturePhase.allCases.filter { phases.contains($0) }
    lastPhases = ordered.map(\.rawValue).joined(separator: ",")

    coordinator.start(
      level: LevelRef(
        slug: SessionID.slug(trimmedLevel) ?? "l1", name: trimmedLevel, index: 1),
      room: SlugRef(slug: SessionID.slug(trimmedRoom) ?? "room", name: trimmedRoom),
      phases: ordered,
      notes: notes.isEmpty ? nil : notes)
  }
}
