import SwiftUI
import VividHomeCore

/// Naming a room, and the level it is on.
///
/// This exists because the house screen shipped without it: the only way into a
/// capture was tapping a room that already had one, so a room could never be
/// added and a second level could never be created. The screen whose whole
/// purpose was to make a two-storey house recordable made it impossible — the
/// same failure as the plan screen, which shipped with `place` reachable only
/// from the drag handler of a pin that did not exist yet.
struct NewRoomSheet: View {
  let levels: [LevelRef]
  let onCreate: (LevelRef, String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var room = ""
  @State private var levelSlug: String = ""
  @State private var newLevelName = ""
  @State private var newLevelIndex = 1

  /// Sentinel for "a level that does not exist yet". Not a slug, so it cannot
  /// collide with a real one.
  private static let newLevelTag = "\u{0000}new"

  private var creatingLevel: Bool { levelSlug == Self.newLevelTag || levels.isEmpty }

  private var resolvedLevel: LevelRef? {
    if creatingLevel {
      let name = newLevelName.trimmingCharacters(in: .whitespaces)
      guard let slug = SessionID.slug(name) else { return nil }
      return LevelRef(slug: slug, name: name, index: newLevelIndex)
    }
    return levels.first { $0.slug == levelSlug }
  }

  private var trimmedRoom: String { room.trimmingCharacters(in: .whitespaces) }

  private var canCreate: Bool {
    resolvedLevel != nil && SessionID.slug(trimmedRoom) != nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Room") {
          TextField("Kitchen", text: $room)
            .textInputAutocapitalization(.words)
        }

        Section {
          if !levels.isEmpty {
            Picker("Level", selection: $levelSlug) {
              ForEach(levels, id: \.slug) { level in
                Text(level.name).tag(level.slug)
              }
              Text("New level…").tag(Self.newLevelTag)
            }
          }

          if creatingLevel {
            TextField("Level 2", text: $newLevelName)
              .textInputAutocapitalization(.words)
            // Asked rather than guessed. The storey decides the order levels
            // read in, and it cannot be derived from a name: "Basement",
            // "Ground" and "Lower" all mean below, and nothing in the string
            // says so.
            Stepper(
              "Storey \(newLevelIndex)", value: $newLevelIndex, in: -2...60)
          }
        } header: {
          Text("Level")
        } footer: {
          if creatingLevel {
            Text("Storey orders the levels: 0 is the ground floor, negatives are below it.")
          }
        }
      }
      .navigationTitle("New room")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            if let level = resolvedLevel { onCreate(level, trimmedRoom) }
          }
          .disabled(!canCreate)
        }
      }
      .onAppear {
        // Default to the level most recently worked on, which on a site is
        // nearly always the one the next room is also on.
        if levelSlug.isEmpty { levelSlug = levels.first?.slug ?? Self.newLevelTag }
        newLevelIndex = (levels.map(\.index).max() ?? 0) + 1
      }
    }
  }
}
