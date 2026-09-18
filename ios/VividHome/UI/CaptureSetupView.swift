import SwiftUI
import VividHomeCore

/// The last step before recording: which trades this pass exposes, and a note.
///
/// The level and the room are chosen on the house screen and arrive here
/// settled. They used to be editable here as well, which meant two screens
/// could set the same two strings — the shape of most of what has broken on
/// this project. One screen chooses; this one records.
struct CaptureSetupView: View {
  @ObservedObject var coordinator: CaptureCoordinator
  @ObservedObject var plans: PlanStore
  let level: LevelRef
  let room: SlugRef
  let onAddPlan: () -> Void
  let onShowCoverage: () -> Void
  let onShowSessions: () -> Void
  let onBackToProject: () -> Void

  @State private var notes = ""
  /// Defaults to the last set used, which on a site is nearly always the right
  /// answer: trades finish a floor before they move on.
  @AppStorage("lastPhases") private var lastPhases = ""
  @State private var phases: Set<CapturePhase> = []

  private var roomIsPlaced: Bool {
    guard let plan = plans.plans[levelSlug] else { return false }
    return plan.placement(of: room.slug) != nil
  }

  private var canStart: Bool { !phases.isEmpty }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Level", value: level.name)
          LabeledContent("Room", value: room.name)
        } header: {
          Text("Where")
        } footer: {
          Text("Chosen on the house screen. Tap House above to pick a different room.")
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
                Label("Plan for \(level.name)", systemImage: "map")
                Spacer()
                Text(placementSummary(plan))
                  .font(.footnote).foregroundStyle(.secondary)
              }
            }
          } else {
            Button(action: onAddPlan) {
              Label("Add a plan for \(level.name)", systemImage: "map")
            }
          }

          // A room typed here is fine — a hallway may not be labelled on the
          // drawing at all — but it has to end up on the plan, or the capture
          // has nothing to be placed against (ADR-0026).
          if plans.plans[levelSlug] != nil, !roomIsPlaced {
            Button(action: onShowCoverage) {
              Label {
                Text("\(room.name) is not on the plan yet")
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
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("House", systemImage: "chevron.left", action: onBackToProject)
        }
      }
      .onAppear(perform: restorePhases)
    }
  }

  private var levelSlug: String { level.slug }

  private func placementSummary(_ plan: PlanFile) -> String {
    plan.placement(of: room.slug) != nil ? "this room placed" : "\(plan.rooms.count) placed"
  }

  private func restorePhases() {
    phases = Set(lastPhases.split(separator: ",").compactMap { CapturePhase(rawValue: String($0)) })
  }

  private func start() {
    let ordered = CapturePhase.allCases.filter { phases.contains($0) }
    lastPhases = ordered.map(\.rawValue).joined(separator: ",")
    coordinator.start(
      level: level, room: room, phases: ordered, notes: notes.isEmpty ? nil : notes)
  }
}
