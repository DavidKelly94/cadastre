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
  @ObservedObject var link: PCLink
  let onDone: () -> Void

  @State private var rows: [Row] = []
  @State private var sharing: URL?
  @State private var failure: String?
  @State private var freeBytes: Int?
  @State private var selected: Set<String> = []
  @State private var confirmingDelete = false
  @State private var confirmingValidatedDelete = false
  @Environment(\.editMode) private var editMode

  /// A session as the list shows it. Read once when the list appears rather
  /// than held live: these are finished sessions and their numbers are final.
  struct Row: Identifiable {
    var id: String { layout.root.lastPathComponent }
    var layout: SessionLayout
    var manifest: Manifest?
    var bytes: Int
    var incomplete: Bool
  }

  private var documents: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  private var store: SessionStore { SessionStore(documents: documents) }

  private var editing: Bool { editMode?.wrappedValue.isEditing == true }

  private var selectedBytes: Int {
    rows.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes }
  }

  /// The captures the PC says it has ingested and validated: the only ones
  /// that are safe to delete here, on the PC's word rather than the phone's.
  private var validatedOnPC: [Row] {
    guard let index = link.index else { return [] }
    let ids = index.validatedSessionIDs
    return rows.filter { ids.contains($0.id) }
  }

  private var validatedBytes: Int { validatedOnPC.reduce(0) { $0 + $1.bytes } }

  var body: some View {
    NavigationStack {
      Group {
        if rows.isEmpty {
          ContentUnavailableView(
            "No captures yet", systemImage: "square.stack.3d.up",
            description: Text("Recorded rooms show up here, and stay until you delete them."))
        } else {
          List(selection: $selected) {
            if !validatedOnPC.isEmpty {
              Section {
                Button(role: .destructive) {
                  confirmingValidatedDelete = true
                } label: {
                  Label(
                    "Delete the \(validatedOnPC.count) capture\(validatedOnPC.count == 1 ? "" : "s") "
                      + "the PC has validated (\(Self.bytes(validatedBytes)))",
                    systemImage: "trash")
                }
              } footer: {
                Text(pcFooter)
              }
            }
            Section {
              ForEach(rows) { row in
                NavigationLink {
                  SessionDetailView(row: row)
                } label: {
                  label(row)
                }
              }
              .onDelete(perform: delete)
            } header: {
              // What deleting would gain, against the floor capture refuses at.
              // A 5-minute room is 300-800 MB, so this number moves fast.
              Text(freeSpace)
            } footer: {
              Text(listFooter)
            }
          }
        }
      }
      .navigationTitle("Captures")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if !rows.isEmpty { EditButton() }
        }
        ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
        ToolbarItem(placement: .bottomBar) {
          if editing {
            Button(role: .destructive) {
              confirmingDelete = true
            } label: {
              Text(selected.isEmpty
                ? "Select captures to delete"
                : "Delete \(selected.count) (\(Self.bytes(selectedBytes)))")
            }
            .disabled(selected.isEmpty)
          }
        }
      }
      .confirmationDialog(
        "Delete \(selected.count) capture\(selected.count == 1 ? "" : "s")?",
        isPresented: $confirmingDelete, titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive, action: deleteSelected)
      } message: {
        Text("Only captures already copied to the PC should go. This cannot be undone.")
      }
      .confirmationDialog(
        "Delete \(validatedOnPC.count) capture\(validatedOnPC.count == 1 ? "" : "s") from this iPhone?",
        isPresented: $confirmingValidatedDelete, titleVisibility: .visible
      ) {
        Button("Delete from this iPhone", role: .destructive, action: deleteValidated)
      } message: {
        Text("The PC listed each of these as ingested and validated. Nothing changes on the PC. "
          + "This cannot be undone here.")
      }
      .onAppear(perform: reload)
      .task { await link.refreshIfStale() }
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
          chip("unfinished", .orange)
        }
        // The PC's word, when it has been asked: "on the PC" is validated;
        // held-but-unchecked is said as such, because it is not the same.
        switch link.index?.holding(of: row.id) {
        case .validated?:
          chip("on the PC", .green)
        case .held?:
          chip("on the PC, unchecked", .secondary)
        case .absent?, nil:
          EmptyView()
        }
      }
      Text(subtitle(row)).font(.footnote).foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }

  private func chip(_ text: String, _ tone: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6).padding(.vertical, 2)
      .background(tone.opacity(0.2), in: Capsule())
      .foregroundStyle(tone)
  }

  private var pcFooter: String {
    guard let index = link.index, let checkedAt = link.checkedAt else { return "" }
    return "\(index.store) listed them as ingested and validated at "
      + "\(checkedAt.formatted(date: .omitted, time: .shortened)). Nothing is deleted on the PC."
  }

  private var listFooter: String {
    let base = "Deleting the app deletes every capture still on the phone."
    if link.index != nil {
      return "Captures marked \"on the PC\" are the ones the PC says it validated. " + base
    }
    if link.isConfigured {
      return "The PC did not answer, so which captures it has is unknown. Copy a session "
        + "to the PC before deleting it here. " + base
    }
    return "Connect to the PC (project screen → PC) to see which captures it already has. "
      + "Copy a session to the PC before deleting it here. " + base
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
    freeBytes = Self.freeBytes(on: documents)
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
    freeBytes = Self.freeBytes(on: documents)
  }

  private func deleteSelected() {
    delete(rows.filter { selected.contains($0.id) })
    selected = []
    editMode?.wrappedValue = .inactive
  }

  private func deleteValidated() {
    delete(validatedOnPC)
  }

  private func delete(_ doomed: [Row]) {
    let store = store
    for row in doomed {
      do {
        try store.delete(at: row.layout)
      } catch {
        failure = error.localizedDescription
        break
      }
      rows.removeAll { $0.id == row.id }
    }
    freeBytes = Self.freeBytes(on: documents)
  }

  /// What deleting would gain, against the floor capture refuses at.
  private var freeSpace: String {
    guard let freeBytes else { return "Free space unknown" }
    let floor = HealthPolicy.minimumFreeBytesToStart
    let state =
      freeBytes < floor
      ? "capture will not start below \(Self.bytes(floor))"
      : "capture stops starting below \(Self.bytes(floor))"
    return "\(Self.bytes(freeBytes)) free on this iPhone; \(state)"
  }

  /// Free space as iOS would let this app use it, which is the number that
  /// decides whether a capture can start, not the raw volume figure.
  static func freeBytes(on url: URL) -> Int? {
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage.map { Int($0) }
  }

  static func bytes(_ value: Int) -> String {
    let mb = Double(value) / 1_000_000
    return mb >= 1000 ? String(format: "%.2f GB", mb / 1000) : String(format: "%.0f MB", mb)
  }

  /// The manifest stores ISO 8601 with offset because that is the contract; a
  /// person reading a list of their own captures wants the local date. If it
  /// does not parse, show the string as written rather than nothing — an
  /// unparseable timestamp is worth seeing.
  static func started(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: iso) ?? {
      parser.formatOptions = [.withInternetDateTime]
      return parser.date(from: iso)
    }()
    guard let date else { return iso }
    return date.formatted(date: .abbreviated, time: .shortened)
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
          detail("Started", SessionListView.started(manifest.capture.startedAt))
          detail("Duration", String(format: "%d:%02d",
            Int(manifest.capture.duration) / 60, Int(manifest.capture.duration) % 60))
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
        NavigationLink {
          SessionPhotosView(layout: row.layout, manifest: row.manifest)
        } label: {
          Label("Photos", systemImage: "photo.on.rectangle")
        }
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
