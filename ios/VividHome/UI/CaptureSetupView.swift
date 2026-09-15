import SwiftUI
import VividHomeCore

/// What a capture needs before it can start: a level, a room and at least one
/// trade. Deliberately small — the designed Project and Room screens will
/// replace it, and until they exist this is what stands between the capture
/// layer and a real session on disk.
struct CaptureSetupView: View {
  @ObservedObject var coordinator: CaptureCoordinator

  @State private var levelName = "Level 1"
  @State private var roomName = ""
  @State private var notes = ""
  /// Defaults to the last set used, which on a site is nearly always the right
  /// answer: trades finish a floor before they move on.
  @AppStorage("lastPhases") private var lastPhases = ""
  @State private var phases: Set<CapturePhase> = []

  private var canStart: Bool {
    !roomName.trimmingCharacters(in: .whitespaces).isEmpty && !phases.isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Where") {
          TextField("Level", text: $levelName)
          TextField("Room", text: $roomName)
            .textInputAutocapitalization(.words)
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

        Section("Notes") {
          TextField("Optional", text: $notes, axis: .vertical).lineLimit(1...4)
        }

        Section {
          Button("Start capture") { start() }
            .disabled(!canStart)
        }
      }
      .navigationTitle("New capture")
      .onAppear(perform: restorePhases)
    }
  }

  private func restorePhases() {
    phases = Set(lastPhases.split(separator: ",").compactMap { CapturePhase(rawValue: String($0)) })
  }

  private func start() {
    let trimmedRoom = roomName.trimmingCharacters(in: .whitespaces)
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
