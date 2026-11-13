import SwiftUI
import VividHomeCore

/// The projects on this phone (ADR-0033): open one, make one, rename one,
/// delete one with everything in it.
///
/// A project is one building. Its captures and plans live in its own folder
/// and the PC keeps it apart from every other, so a rehearsal at home never
/// sits beside the house being built.
struct ProjectListView: View {
  @ObservedObject var link: PCLink
  /// The `sessions` folder: one folder per project.
  let root: URL
  let onOpen: (String) -> Void

  @State private var projects: [ProjectCatalog.Entry] = []
  @State private var naming = false
  @State private var renaming: ProjectCatalog.Entry?
  @State private var deleting: ProjectCatalog.Entry?
  @State private var draft = ""
  @State private var typed = ""
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      Group {
        if projects.isEmpty {
          ContentUnavailableView {
            Label("No projects yet", systemImage: "house")
          } description: {
            Text("A project is one building: its drawings, and every capture of every room.")
          } actions: {
            Button("New project") {
              draft = ""
              naming = true
            }
            .buttonStyle(.borderedProminent)
          }
        } else {
          List {
            ForEach(projects) { project in
              Button {
                onOpen(project.slug)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(project.name).font(.headline).foregroundStyle(.primary)
                  Text(Self.holds(project)).font(.footnote).foregroundStyle(.secondary)
                }
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", role: .destructive) {
                  typed = ""
                  deleting = project
                }
                Button("Rename") {
                  draft = project.name
                  renaming = project
                }
              }
            }
          }
        }
      }
      .navigationTitle("Projects")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("New project", systemImage: "plus") {
            draft = ""
            naming = true
          }
        }
      }
      .alert("New project", isPresented: $naming) {
        TextField("Our house", text: $draft)
        Button("Cancel", role: .cancel) {}
        Button("Create", action: create)
      } message: {
        Text("One building. The name can be changed later.")
      }
      .alert(
        "Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
      ) {
        TextField("Name", text: $draft)
        Button("Cancel", role: .cancel) { renaming = nil }
        Button("Save", action: rename)
      } message: {
        Text("Only the name changes. Captures already made keep the name they were made under.")
      }
      .alert(
        "Delete \(deleting?.name ?? "")?",
        isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
      ) {
        TextField("Type the project's name", text: $typed)
        Button("Cancel", role: .cancel) { deleting = nil }
        Button("Delete", role: .destructive, action: delete)
      } message: {
        Text(deleting.map(warning) ?? "")
      }
      .alert("Could not do that", isPresented: .constant(failure != nil)) {
        Button("OK") { failure = nil }
      } message: {
        Text(failure ?? "")
      }
      .onAppear(perform: reload)
      .task { await link.refreshIfStale() }
    }
  }

  private static func holds(_ project: ProjectCatalog.Entry) -> String {
    let captures = project.captures.count
    return "\(captures) capture\(captures == 1 ? "" : "s") · \(project.plans) plan\(project.plans == 1 ? "" : "s")"
  }

  /// What deleting would lose: everything on the phone, and for good the
  /// captures the PC has not said it holds.
  private func warning(_ project: ProjectCatalog.Entry) -> String {
    let count = project.captures.count
    var text = "\(count) capture\(count == 1 ? "" : "s") and \(project.plans) plan\(project.plans == 1 ? "" : "s") "
      + "are removed from this phone. Nothing on the PC is touched. "
    if count > 0 {
      if let index = link.index {
        let lost = ProjectCatalog.unconfirmed(project, validatedOnPC: index.validatedSessionIDs).count
        text += lost == 0
          ? "The PC has confirmed every capture. "
          : "\(lost) of them the PC has not confirmed it holds: those would be gone for good. "
      } else {
        text += "The PC has not been reached, so none of them is confirmed there. "
      }
    }
    return text + "Type the project's name to delete it."
  }

  private func reload() {
    projects = ProjectCatalog.list(in: root)
  }

  private func create() {
    do {
      let made = try ProjectCatalog.create(name: draft, in: root)
      reload()
      onOpen(made.slug)
    } catch ProjectCatalog.Failure.exists {
      failure = "There is already a project with that name."
    } catch ProjectCatalog.Failure.unusableName {
      failure = "That name has no letters or digits in it."
    } catch {
      failure = error.localizedDescription
    }
  }

  private func rename() {
    guard let project = renaming else { return }
    renaming = nil
    do {
      try ProjectCatalog.rename(project.slug, to: draft, in: root)
      reload()
    } catch {
      failure = "The name was not changed."
    }
  }

  private func delete() {
    guard let project = deleting else { return }
    deleting = nil
    let wanted = project.name.trimmingCharacters(in: .whitespaces).lowercased()
    guard typed.trimmingCharacters(in: .whitespaces).lowercased() == wanted else {
      failure = "The name did not match, so nothing was deleted."
      return
    }
    do {
      try ProjectCatalog.delete(project.slug, in: root)
      reload()
    } catch {
      failure = "The project could not be deleted: \(error.localizedDescription)"
    }
  }
}
