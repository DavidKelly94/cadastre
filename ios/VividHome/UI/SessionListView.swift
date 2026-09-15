import SwiftUI
import VividHomeCore

/// Every capture still on the phone.
///
/// Until this existed a session could only be shared in the moment after it was
/// stopped: Session review held the only share affordance, and tapping Done
/// returned to setup with no way back. That is the wrong shape for how the work
/// actually goes — several rooms in one visit, then everything off to the PC
/// afterwards — and it made the review screen's checks a thing you had to read
/// immediately or lose.
struct SessionListView: View {
  let project: String
  let onDone: () -> Void

  @State private var rows: [Row] = []
  @State private var sharing: URL?
  @State private var failure: String?

  /// A session as the list shows it. Read once when the list appears rather
  /// than held live: these are finished sessions and their numbers are final.
  struct Row: Identifiable {
    var id: String { layout.root.lastPathComponent }
    var layout: SessionLayout
    var manifest: Manifest?
    var bytes: Int
    var incomplete: Bool
  }

  private var store: SessionStore {
    SessionStore(documents: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
  }

  var body: some View {
    NavigationStack {
      Group {
        if rows.isEmpty {
          ContentUnavailableView(
            "No captures yet", systemImage: "square.stack.3d.up",
            description: Text("Recorded rooms show up here, and stay until you delete them."))
        } else {
          List {
            Section {
              ForEach(rows) { row in
                NavigationLink {
                  SessionDetailView(row: row)
                } label: {
                  label(row)
                }
              }
              .onDelete(perform: delete)
            } footer: {
              Text("Copy a session to the PC before deleting it here. "
                + "Deleting the app deletes every capture still on the phone.")
            }
          }
        }
      }
      .navigationTitle("Captures")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
      .onAppear(perform: reload)
      .alert("Could not delete", isPresented: .constant(failure != nil)) {
        Button("OK") { failure = nil }
      } message: {
        Text(failure ?? "")
      }
    }
  }

  private func label(_ row: Row) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(row.manifest?.room.name ?? row.id).font(.headline)
        if row.incomplete {
          // A session the app never finished writing. Shown rather than hidden:
          // it may still hold most of a capture, and `validate` will say.
          Text("unfinished")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.2), in: Capsule())
            .foregroundStyle(.orange)
        }
      }
      Text(subtitle(row)).font(.footnote).foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }

  private func subtitle(_ row: Row) -> String {
    guard let manifest = row.manifest else { return "no manifest" }
    let phases = manifest.phases.map(\.shortName).joined(separator: " + ")
    let size = row.bytes > 0 ? " · \(Self.bytes(row.bytes))" : ""
    return "\(manifest.level.name) · \(phases)\(size)"
  }

  // MARK: - Data

  private func reload() {
    let store = store
    let layouts = (try? store.sessions(inProject: project)) ?? []
    rows = layouts.map { layout in
      let manifest = store.manifest(at: layout)
      return Row(
        layout: layout,
        manifest: manifest,
        bytes: store.countedStats(at: layout).bytes,
        incomplete: manifest?.status != .complete)
    }
  }

  private func delete(at offsets: IndexSet) {
    let store = store
    for index in offsets {
      do {
        try store.delete(at: rows[index].layout)
      } catch {
        failure = error.localizedDescription
        return
      }
    }
    rows.remove(atOffsets: offsets)
  }

  static func bytes(_ value: Int) -> String {
    let mb = Double(value) / 1_000_000
    return mb >= 1000 ? String(format: "%.2f GB", mb / 1000) : String(format: "%.0f MB", mb)
  }
}

/// One past capture: what it holds, and the way off the phone.
struct SessionDetailView: View {
  let row: SessionListView.Row

  var body: some View {
    List {
      if let manifest = row.manifest {
        Section("Capture") {
          detail("Room", manifest.room.name)
          detail("Level", manifest.level.name)
          detail("Trades", manifest.phases.map(\.displayName).joined(separator: ", "))
          detail("Started", manifest.startedAt)
          detail("Duration", String(format: "%d:%02d", Int(manifest.duration) / 60, Int(manifest.duration) % 60))
        }
        Section("Recorded") {
          detail("Keyframes", "\(manifest.stats.keyframes)")
          detail("Stills", "\(manifest.stats.stills)")
          detail("Marker sightings", "\(manifest.stats.markerObservations)")
          detail("Landmarks", "\(manifest.stats.landmarks)")
          detail("On disk", SessionListView.bytes(row.bytes))
        }
        if let notes = manifest.notes, !notes.isEmpty {
          Section("Notes") { Text(notes).font(.footnote) }
        }
      } else {
        Section {
          Text("This session has no readable manifest. Share it anyway — "
            + "`vividhome validate` on the PC will say what is wrong.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }

      Section {
        ShareLink(item: row.layout.root) {
          Label("Share this capture", systemImage: "square.and.arrow.up")
        }
      } footer: {
        Text("Also reachable in the Files app under On My iPhone → VividHome → sessions.")
      }
    }
    .navigationTitle(row.manifest?.room.name ?? "Capture")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func detail(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).multilineTextAlignment(.trailing)
    }
    .font(.footnote)
  }
}
