import SwiftUI
import VividHomeCore

/// The house, by level and room: what has been walked and what has not.
///
/// This sits above capture. Until it existed, one project and one level were
/// reachable because `ContentView` held a level name in a text field, which
/// meant a two-storey house could not be recorded as one building.
///
/// Rooms come from two places and the difference matters. A room with captures
/// is known from its manifests; a room with none is known only because it was
/// placed on the plan. Merging them is what lets the screen say what is left to
/// do rather than only what is done — a list of finished work cannot tell you
/// where to go next.
struct ProjectOverviewView: View {
  let project: String
  @ObservedObject var plans: PlanStore
  let onPick: (LevelRef, String) -> Void

  @State private var digest: ProjectDigest?
  @State private var loading = true

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
        ?? LevelSection(slug: slug, name: slug.capitalized, index: 0, rooms: [], unwalked: [])
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
          ContentUnavailableView(
            "Nothing here yet", systemImage: "house",
            description: Text(
              "Import a plan and place a room, or just start a capture. "
                + "Rooms show up here once either has happened."))
        } else {
          list
        }
      }
      .navigationTitle(digest?.name ?? "Project")
      .navigationBarTitleDisplayMode(.inline)
      .task { await load() }
      .refreshable { await load() }
    }
  }

  private var list: some View {
    List {
      ForEach(sections) { section in
        Section {
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
}
