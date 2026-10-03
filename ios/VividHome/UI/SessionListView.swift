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
  /// For placing a free capture on its level's plan after the fact.
  @ObservedObject var plans: PlanStore
  let onDone: () -> Void

  @State private var rows: [Row] = []
  @State private var sharing: URL?
  @State private var failure: String?
  @State private var freeBytes: Int?
  @State private var selected: Set<String> = []
  @State private var confirmingDelete = false
  @State private var confirmingValidatedDelete = false
  @State private var sending: SendBatch?
  @Environment(\.editMode) private var editMode

  /// The captures a send sheet was opened for.
  struct SendBatch: Identifiable {
    let id = UUID()
    var rows: [Row]
  }

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

  /// The captures the PC does not say it has. With no answer from the PC yet,
  /// that is all of them; the send asks the PC per capture and skips what it
  /// already holds.
  private var notOnPC: [Row] {
    rows.filter { row in
      switch link.index?.holding(of: row.id) {
      case .validated?, .held?: return false
      case .absent?, nil: return true
      }
    }
  }

  private var notOnPCBytes: Int { notOnPC.reduce(0) { $0 + $1.bytes } }

  var body: some View {
    NavigationStack {
      Group {
        if rows.isEmpty {
          ContentUnavailableView(
            "No captures yet", systemImage: "square.stack.3d.up",
            description: Text("Recorded rooms show up here, and stay until you delete them."))
        } else {
          List(selection: $selected) {
            if !notOnPC.isEmpty {
              Section {
                Button {
                  sending = SendBatch(rows: notOnPC)
                } label: {
                  Label(
                    "Send \(notOnPC.count) capture\(notOnPC.count == 1 ? "" : "s") to the PC "
                      + "(\(Self.bytes(notOnPCBytes)))",
                    systemImage: "arrow.up.to.line")
                }
              } footer: {
                Text(sendFooter)
              }
            }
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
                  SessionDetailView(
                    row: row, onPC: link.index?.holding(of: row.id), plans: plans, project: project,
                    onSend: { sending = SendBatch(rows: [row]) }
                  ) {
                    delete([row])
                  }
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
      }
      .safeAreaInset(edge: .bottom) {
        if editing {
          deleteBar
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
      .sheet(item: $sending) { batch in
        SendToPCView(rows: batch.rows, link: link) {
          // The PC's word changed: ask again so the marks follow.
          Task { await link.test() }
        }
      }
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

  /// The edit-mode action, as a strip that cannot be missed: the first walk
  /// found Edit → select → delete hard to discover, and a toolbar item in a
  /// sheet is easy to overlook. Select all is here because the common case is
  /// clearing a whole visit after it has reached the PC.
  private var deleteBar: some View {
    VStack(spacing: 8) {
      HStack {
        Text(selected.isEmpty
          ? "Tap captures to select them"
          : "\(selected.count) selected · \(Self.bytes(selectedBytes))")
          .font(.footnote).foregroundStyle(.secondary)
        Spacer()
        Button(selected.count == rows.count ? "Select none" : "Select all") {
          selected = selected.count == rows.count ? [] : Set(rows.map(\.id))
        }
        .font(.footnote)
      }
      Button(role: .destructive) {
        confirmingDelete = true
      } label: {
        Label(
          selected.isEmpty
            ? "Delete selected captures"
            : "Delete \(selected.count) capture\(selected.count == 1 ? "" : "s") from this iPhone",
          systemImage: "trash")
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .disabled(selected.isEmpty)
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(.bar)
  }

  private var sendFooter: String {
    if link.canSend {
      return "Each goes straight to `vividhome serve --lan` on the PC, which ingests and "
        + "validates it. The Files app is not needed."
    }
    if link.isConfigured {
      return "Sending needs the pairing code `vividhome serve --lan` prints; type it under PC "
        + "on the project screen."
    }
    return "Set the PC's address and pairing code under PC on the project screen to send "
      + "captures without the Files app."
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
    // The date first: the same room walked three times is three rows, and the
    // date is what tells them apart.
    return "\(Self.started(manifest.capture.startedAt)) · \(manifest.level.name) · \(phases)\(size)"
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
    if freeBytes < floor {
      return "\(Self.bytes(freeBytes)) free on this iPhone. A capture needs "
        + "\(Self.bytes(floor)) to start, so none can until something is deleted."
    }
    return "\(Self.bytes(freeBytes)) free on this iPhone. A capture needs \(Self.bytes(floor)) to start."
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

/// One past capture: what it holds, the way off the phone, and the way off
/// the phone for good.
struct SessionDetailView: View {
  let row: SessionListView.Row
  /// The PC's word on this capture, when it has been asked.
  let onPC: ServerIndex.Holding?
  @ObservedObject var plans: PlanStore
  let project: String
  let onSend: () -> Void
  let onDelete: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var confirming = false
  /// The placement beside the plans, read each time this appears so a
  /// placement just made on the next screen shows on the way back.
  @State private var placement: AlignmentFile?

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
        // Where the capture sits on the plan (ADR-0031). A guided capture
        // placed itself at Stop; a free one is placed here, afterwards.
        HStack {
          Text("Placement").foregroundStyle(.secondary)
          Spacer()
          Text(placementText).multilineTextAlignment(.trailing)
        }
        .font(.footnote)
        NavigationLink {
          PlanPlacementView(plans: plans, layout: row.layout, manifest: row.manifest, project: project)
        } label: {
          Label(placement == nil ? "Place on the plan" : "Adjust the placement", systemImage: "scope")
        }
      } header: {
        Text("On the plan")
      } footer: {
        Text(placementFooter)
      }

      Section {
        NavigationLink {
          SessionPhotosView(layout: row.layout, manifest: row.manifest)
        } label: {
          Label("Photos", systemImage: "photo.on.rectangle")
        }
        if onPC != .validated && onPC != .held {
          Button(action: onSend) {
            Label("Send this capture to the PC", systemImage: "arrow.up.to.line")
          }
        }
        ShareLink(item: row.layout.root) {
          Label("Share this capture", systemImage: "square.and.arrow.up")
        }
      } footer: {
        Text(
          (onPC == .validated || onPC == .held
            ? "The PC already has this capture. "
            : "Send goes straight to `vividhome serve --lan` on the PC. ")
            + "Also reachable in the Files app under On My iPhone → VividHome → sessions.")
      }

      Section {
        Button(role: .destructive) {
          confirming = true
        } label: {
          Label("Delete this capture from the iPhone", systemImage: "trash")
        }
      } footer: {
        Text(deleteFooter)
      }
    }
    .navigationTitle(row.manifest?.room.name ?? "Capture")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      let project = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent(project, isDirectory: true)
      placement = AlignmentFile.read(at: AlignmentFile.url(projectDirectory: project, sessionID: row.id))
    }
    .confirmationDialog(
      "Delete this capture from the iPhone?", isPresented: $confirming, titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        onDelete()
        dismiss()
      }
    } message: {
      Text(deleteFooter)
    }
  }

  private var placementText: String {
    guard let placement else { return "Not placed" }
    let how = placement.method == "guided" ? "during capture" : "paired on the plan"
    return "Placed \(how), \(Int((placement.rmsM * 100).rounded())) cm"
  }

  private var placementFooter: String {
    guard let manifest = row.manifest else { return "Pairing needs the capture's landmarks and a plan with a scale." }
    guard let plan = plans.plans[manifest.level.slug] else {
      return "No plan for \(manifest.level.name) yet. Add one on the house screen to place this capture."
    }
    if !plan.isCalibrated {
      return "The plan for \(manifest.level.name) has no scale yet. Set it on the plan screen first."
    }
    return placement == nil
      ? "Pair two or more of the capture's landmarks with their places on the drawing. The PC adopts the result with the capture."
      : "Adjusting rewrites the placement beside the plans; the PC adopts the newer one when the capture is sent."
  }

  private var deleteFooter: String {
    switch onPC {
    case .validated?:
      return "The PC has this capture and validated it. Deleting here frees "
        + "\(SessionListView.bytes(row.bytes)) and changes nothing on the PC."
    case .held?:
      return "The PC has this capture but has not validated it. Keep it until it does."
    case .absent?:
      return "The PC does not have this capture. Send it first; deleting here is the only copy gone."
    case nil:
      return "Whether the PC has this capture is unknown. Send it first unless you are sure. "
        + "This cannot be undone."
    }
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
