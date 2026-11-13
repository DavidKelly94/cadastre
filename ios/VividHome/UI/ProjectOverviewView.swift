import SwiftUI
import UIKit
import VividHomeCore

/// The house, by level and room: what has been walked and what has not.
///
/// This sits above capture. Until it existed, one project and one level were
/// reachable because `ContentView` held a level name in a text field, which
/// meant a two-storey house could not be recorded as one building.
///
/// Each level leads with its plan. The first walk of the house screen landed on
/// a bare room list with the plan nowhere in sight, and the owner's reaction was
/// the right one: the plan is what a house looks like, the rooms are what is on
/// it, and they belong together. The card is the plan with its rooms pinned and
/// shaded by what has been walked; tapping it opens the full plan to place and
/// correct rooms. A level with no plan says so and offers to import one.
///
/// Rooms come from two places and the difference matters. A room with captures
/// is known from its manifests; a room with none is known only because it was
/// placed on the plan. Merging them is what lets the screen say what is left to
/// do rather than only what is done — a list of finished work cannot tell you
/// where to go next.
struct ProjectOverviewView: View {
  let project: String
  /// The project's name as the owner gave it, and the way back to the list
  /// of projects (ADR-0033).
  var projectName: String = ""
  var onShowProjects: (() -> Void)? = nil
  /// Opens the list of captures: review, send to the PC, delete. It used to
  /// be reachable only from a room's setup screen, under "Past captures",
  /// which the owner had to ask the way to (2026-11-13).
  var onShowCaptures: (() -> Void)? = nil
  @ObservedObject var plans: PlanStore
  @ObservedObject var link: PCLink
  let onPick: (LevelRef, String) -> Void

  @State private var digest: ProjectDigest?
  @State private var loading = true
  @State private var adding = false
  @State private var showingPC = false
  @State private var rendering: RenderingTarget?
  @State private var planSheet: PlanSheet?
  /// Naming a level and saying which floor it is, to import its plan before
  /// anything is recorded there.
  @State private var namingLevel = false
  @State private var draftLevel = ""
  @State private var draftIndex = 0
  /// Feet and inches or metric, for every length the app shows.
  @AppStorage(AppUnits.key) private var unitsChoice = Units.imperial.rawValue

  private var store: SessionStore {
    SessionStore(documents: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
  }

  /// Every level worth a section: those with captures, and those with a plan
  /// but nothing recorded yet.
  private var sections: [LevelSection] {
    var byLevel: [String: LevelSection] = [:]

    for level in digest?.levels ?? [] {
      byLevel[level.level] = LevelSection(
        slug: level.level, name: level.name, index: level.index, rooms: level.rooms,
        unwalked: [])
    }

    for (slug, plan) in plans.plans {
      let placed = plan.rooms.map(\.room)
      var section =
        byLevel[slug]
        ?? LevelSection(
          slug: slug, name: plan.levelRef.name, index: plan.levelRef.index, rooms: [],
          unwalked: [])
      let walked = Set(section.rooms.map(\.room))
      section.unwalked = placed.filter { !walked.contains($0) }.sorted()
      byLevel[slug] = section
    }

    return byLevel.values.sorted {
      $0.index == $1.index ? $0.name < $1.name : $0.index > $1.index
    }
  }

  private var roomTotal: Int {
    sections.reduce(0) { $0 + $1.rooms.count + $1.unwalked.count }
  }

  var body: some View {
    NavigationStack {
      Group {
        if loading {
          ProgressView().controlSize(.large)
        } else if sections.isEmpty {
          // A level appears once it has a capture or a plan, and the plan
          // import lived on the level, so an empty house had no way to start
          // from the drawing (found clearing the project before framing).
          ContentUnavailableView {
            Label("Nothing here yet", systemImage: "house")
          } description: {
            Text(
              "Start from the drawing: import a plan for the first level, set its scale and "
                + "outline the rooms. Or tap New room to record without one.")
          } actions: {
            Button("Import a plan") {
              draftLevel = ""
              draftIndex = 0
              namingLevel = true
            }
            .buttonStyle(.borderedProminent)
          }
        } else {
          list
        }
      }
      .navigationTitle(projectName.isEmpty ? (digest?.name ?? "Project") : projectName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if let onShowProjects {
          ToolbarItem(placement: .topBarLeading) {
            Button("Projects", systemImage: "square.grid.2x2", action: onShowProjects)
          }
        }
        ToolbarItem(placement: .topBarLeading) {
          Button("PC", systemImage: "desktopcomputer") { showingPC = true }
        }
        if let onShowCaptures {
          // A word, not an icon: the wand taught that an unlabeled button
          // is one nobody presses.
          ToolbarItem(placement: .primaryAction) {
            Button("Captures", action: onShowCaptures)
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("New room", systemImage: "plus") { adding = true }
        }
      }
      .sheet(isPresented: $namingLevel) {
        // A sheet, not an alert: the floor number is asked for with the name,
        // and an alert cannot hold a stepper. Without the number a level made
        // from its plan was floor 0, a basement included.
        NavigationStack {
          Form {
            Section {
              TextField("Basement", text: $draftLevel)
                .textInputAutocapitalization(.words)
              Stepper("Floor \(draftIndex)", value: $draftIndex, in: -5...60)
            } footer: {
              Text(
                "The name as you would say it: Main Floor, Basement, Upstairs. "
                  + "The floor number orders the levels: 0 is the ground floor, "
                  + "-1 a basement, 1 the floor above.")
            }
          }
          .navigationTitle("New level")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") { namingLevel = false }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button("Choose its plan") {
                let name = draftLevel.trimmingCharacters(in: .whitespaces)
                guard let slug = SessionID.slug(name) else { return }
                namingLevel = false
                planSheet = .importPlan(
                  LevelSection(slug: slug, name: name, index: draftIndex, rooms: [], unwalked: []))
              }
              .disabled(SessionID.slug(draftLevel) == nil)
            }
          }
        }
        .presentationDetents([.medium])
      }
      .sheet(isPresented: $adding) {
        NewRoomSheet(levels: knownLevels) { level, room in
          adding = false
          onPick(level, room)
        }
      }
      .sheet(isPresented: $showingPC) {
        PCSettingsView(link: link) {
          showingPC = false
          Task { await link.test() }
        }
      }
      .fullScreenCover(item: $rendering) { target in
        RenderingView(
          url: target.url, title: target.title, generatedAt: target.generatedAt
        ) { rendering = nil }
      }
      .sheet(item: $planSheet) { which in
        switch which {
        case .coverage(let section):
          PlanCoverageView(
            store: plans, level: section.slug,
            coverage: plans.coverage(forLevel: section.slug), currentRoom: nil
          ) {
            planSheet = nil
            plans.reload()
          }
        case .importPlan(let section):
          PlanImportView(store: plans, levelName: section.name, levelIndex: section.index) {
            planSheet = nil
            plans.reload()
          }
        }
      }
      .task { await load() }
      .task { await link.refreshIfStale() }
      .refreshable {
        await load()
        if link.isConfigured { await link.test() }
      }
    }
  }

  private var list: some View {
    List {
      ForEach(sections) { section in
        Section {
          // The plan first, with the rooms on it. Then the rooms as a list.
          if let plan = plans.plans[section.slug] {
            Button {
              planSheet = .coverage(section)
            } label: {
              PlanCard(
                plans: plans, plan: plan, coverage: plans.coverage(forLevel: section.slug))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
          } else {
            Button {
              planSheet = .importPlan(section)
            } label: {
              HStack {
                Label("Import a plan for \(section.name)", systemImage: "map")
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
              }
            }
            .buttonStyle(.plain)
          }
          // What the PC made of this level, when it has made anything and is
          // reachable (ADR-0028). Absent rather than disabled otherwise: a row
          // that cannot be tapped says nothing about why.
          if let url = link.inspectURL(project: project, level: section.slug) {
            Button {
              rendering = RenderingTarget(
                url: url, title: section.name, generatedAt: link.index?.generated)
            } label: {
              HStack {
                Label("Rendering on the PC", systemImage: "map")
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
              }
            }
            .buttonStyle(.plain)
          }
          ForEach(section.rooms, id: \.room) { room in
            Button {
              onPick(ref(for: section), room.room)
            } label: {
              walked(room)
            }
            .buttonStyle(.plain)
          }
          ForEach(section.unwalked, id: \.self) { room in
            Button {
              onPick(ref(for: section), room)
            } label: {
              unwalked(room)
            }
            .buttonStyle(.plain)
          }
        } header: {
          Text(section.name)
        }
      }
      // A level appears once it has a capture or a plan, and a plan could
      // only be imported onto a level that was already there: with one floor
      // set up, the next floor's drawing had no way in short of recording
      // on it first.
      Section {
        Button {
          draftLevel = ""
          draftIndex = 0
          namingLevel = true
        } label: {
          Label("Add a level from a plan", systemImage: "square.stack.3d.up")
        }
      }
      Section {
        Picker("Measurements", selection: $unitsChoice) {
          Text("Feet and inches").tag(Units.imperial.rawValue)
          Text("Metric").tag(Units.metric.rawValue)
        }
      } footer: {
        Text("What the app shows. Captures are always recorded in meters.")
      }
    } 
    .safeAreaInset(edge: .top) { summary }
  }

  private var summary: some View {
    let captured = digest?.capturedRooms ?? 0
    return HStack(spacing: 6) {
      Text("\(sections.count) level\(sections.count == 1 ? "" : "s")")
      Text("·")
      Text("\(roomTotal) room\(roomTotal == 1 ? "" : "s")")
      Text("·")
      // Rooms walked at least once, not a completion figure: what fraction of
      // the trades a room still owes is a question the app cannot answer, since
      // no room needs every trade.
      Text("\(captured) walked")
      Spacer()
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private func walked(_ room: RoomDigest) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(room.name).font(.headline)
      Text(room.orderedPhases.map(\.displayName).joined(separator: " · "))
        .font(.footnote).foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }

  private func unwalked(_ room: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(room.capitalized).font(.headline).foregroundStyle(.secondary)
        Text("on the plan, not walked").font(.footnote).foregroundStyle(.tertiary)
      }
      Spacer()
      Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }

  /// The level a pick belongs to. A section built only from a plan has no
  /// manifest to take a storey index from, so it gets 0 — wrong only in the
  /// ordering of a level nothing has been captured on yet, which the first
  /// capture corrects.
  private func ref(for section: LevelSection) -> LevelRef {
    LevelRef(slug: section.slug, name: section.name, index: section.index)
  }

  /// The levels already known, for the new-room sheet to offer. A new level is
  /// created there rather than here, so this only has to list.
  private var knownLevels: [LevelRef] {
    sections.map { LevelRef(slug: $0.slug, name: $0.name, index: $0.index) }
  }

  private func load() async {
    let store = store
    let project = project
    let built = await Task.detached(priority: .userInitiated) { () -> ProjectDigest in
      let layouts = (try? store.sessions(inProject: project)) ?? []
      let manifests = layouts.compactMap { store.manifest(at: $0) }
      return ProjectDigest.make(project: project, from: manifests)
    }.value
    digest = built
    loading = false
  }

  /// Named LevelSection rather than Section because SwiftUI has a Section and
  /// this view uses it. A private helper sharing a name with a symbol already in
  /// scope turns the next small mistake at any of these call sites into a
  /// diagnostic about the wrong type — which cost a build earlier this week when
  /// a helper called `stat` resolved to Darwin's POSIX struct.
  struct LevelSection: Identifiable {
    var id: String { slug }
    var slug: String
    var name: String
    var index: Int
    var rooms: [RoomDigest]
    var unwalked: [String]
  }

  /// A page to open full screen: the URL is the identity.
  struct RenderingTarget: Identifiable {
    var id: String { url.absoluteString }
    var url: URL
    var title: String
    var generatedAt: Date?
  }

  /// The plan sheets this screen opens, per level.
  enum PlanSheet: Identifiable {
    case coverage(LevelSection)
    case importPlan(LevelSection)

    var id: String {
      switch self {
      case .coverage(let section): return "coverage-" + section.slug
      case .importPlan(let section): return "import-" + section.slug
      }
    }
  }
}

/// A level's plan with its rooms on it, as a card in the house list.
///
/// The same drawing, pins and shading as `PlanCoverageView`, at a glance and
/// without the editing: tapping the card opens that screen. Rooms are drawn
/// where the owner put them, shaded by how many passes have been walked, and
/// a room on the plan that nothing has been recorded in stays hollow — which
/// is the point of showing the plan here at all: what is left to do, where.
private struct PlanCard: View {
  @ObservedObject var plans: PlanStore
  let plan: PlanFile
  let coverage: [String: (done: Int, total: Int)]

  @State private var image: UIImage?
  /// The stored raster's pixel size. Room pins are stored in those pixels
  /// (§13), and the card draws a shrunk copy, so the pins must be scaled from
  /// this and never from the copy: the first walk had every pin pushed off the
  /// bottom-right of the card by exactly that mistake.
  @State private var rasterSize: CGSize = .zero

  /// Tall enough to read a floor, short enough that the rooms stay on screen.
  private static let height: CGFloat = 230

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color(.secondarySystemBackground)
      if let image, rasterSize.width > 0 {
        GeometryReader { outer in
          let fitted = PlanCoverageView.fit(rasterSize, into: outer.size)
          let originX = (outer.size.width - fitted.width) / 2
          let originY = (outer.size.height - fitted.height) / 2
          let scale = fitted.width / rasterSize.width

          ZStack(alignment: .topLeading) {
            Image(uiImage: image)
              .resizable().scaledToFit()
              .frame(width: fitted.width, height: fitted.height)
              .offset(x: originX, y: originY)
            ForEach(plan.rooms, id: \.room) { room in
              pin(room, at: CGPoint(x: originX + room.x * scale, y: originY + room.y * scale))
            }
          }
        }
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      HStack(spacing: 6) {
        Image(systemName: "map").font(.caption2)
        Text(cardLabel)
        Spacer()
        Text("Open").foregroundStyle(Color.accentColor)
      }
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(.regularMaterial)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: Self.height)
    .contentShape(Rectangle())
    .task(id: plan.image) {
      // The stored raster is up to 4096 px on its long edge; the card is a few
      // hundred points wide. Decode and shrink off the main thread.
      let plans = plans
      let plan = plan
      let loaded = await Task.detached(priority: .userInitiated) { () -> (UIImage, CGSize)? in
        guard let full = plans.image(for: plan) else { return nil }
        return (PlanStore.downsampled(full, maxEdge: 1200), full.size)
      }.value
      image = loaded?.0
      rasterSize = loaded?.1 ?? .zero
    }
  }

  /// Rooms placed, and whether the drawing has a scale yet (ADR-0030).
  private var cardLabel: String {
    let rooms = plan.rooms.isEmpty
      ? "No rooms placed yet"
      : "\(plan.rooms.count) room\(plan.rooms.count == 1 ? "" : "s") placed"
    return plan.isCalibrated ? rooms : rooms + " · no scale yet"
  }

  private func pin(_ room: PlanRoom, at point: CGPoint) -> some View {
    let done = coverage[room.room]?.done ?? 0
    let total = coverage[room.room]?.total ?? 0
    let fraction = total == 0 ? 0 : Double(done) / Double(total)
    return VStack(spacing: 2) {
      Circle()
        .fill(PlanCoverageView.shade(fraction))
        .overlay(Circle().strokeBorder(PlanCoverageView.ring(fraction), lineWidth: 2))
        .frame(width: 12, height: 12)
      Text(room.room)
        .font(.system(size: 9, weight: .semibold))
        .padding(.horizontal, 3).padding(.vertical, 1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
    }
    .position(point)
  }
}
