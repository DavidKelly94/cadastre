import ARKit
import SwiftUI
import VividHomeCore

/// The app's route: the house, then one room of it.
///
/// The project screen chooses the level and the room; everything below it —
/// setup, capture, review — is the leaf. Before it existed a level was a text
/// field here, which is why only one level was ever reachable and a two-storey
/// house could not be recorded as one building.
struct ContentView: View {
  @StateObject private var coordinator = CaptureCoordinator()
  @StateObject private var plans = PlanStore(project: CaptureCoordinator.projectSlug)
  @State private var sheet: Sheet?
  /// Nil until the house screen chooses one, which keeps that screen the root
  /// rather than something reachable only by backing out of capture.
  ///
  /// The whole LevelRef, not its name: the slug is derivable from the name and
  /// so must not be copied, but the storey index is not derivable from
  /// anything — "Basement", "Ground" and "Lower" all mean below and no string
  /// says so — so it has to be carried. Passing only the name is what left
  /// every manifest claiming storey 1.
  @State private var chosen: Choice?

  private enum Sheet: Int, Identifiable {
    case importPlan
    case coverage
    case sessions
    var id: Int { rawValue }
  }

  private var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
  }

  private var supportsSceneReconstruction: Bool {
    ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
  }

  var body: some View {
    Group {
      if !supportsSceneReconstruction {
        unsupported
      } else {
        switch coordinator.phase {
        case .setup:
          if let chosen {
            CaptureSetupView(
              coordinator: coordinator,
              plans: plans,
              level: chosen.level,
              room: chosen.room,
              onAddPlan: { sheet = .importPlan },
              onShowCoverage: { sheet = .coverage },
              onShowSessions: { sheet = .sessions },
              onBackToProject: { self.chosen = nil })
          } else {
            ProjectOverviewView(
              project: CaptureCoordinator.projectSlug,
              plans: plans,
              onPick: { level, room in
                let slug = SessionID.slug(room) ?? "room"
                chosen = Choice(level: level, room: SlugRef(slug: slug, name: room))
              })
          }
        case .recording:
          CaptureHUDView(
            coordinator: coordinator,
            controller: coordinator.controller,
            recorder: coordinator.recorder)
        case .finishing(let message):
          finishing(message)
        case .review(let summary):
          SessionReviewView(summary: summary) {
            coordinator.backToSetup()
            // Back to the house rather than to setup with the room still in it:
            // the next room is a different room, and the common case after
            // finishing one is picking the next.
            chosen = nil
          }
        case .failed(let message):
          failure(message)
        }
      }
    }
    .sheet(item: $sheet) { which in
      switch which {
      case .importPlan:
        PlanImportView(store: plans, levelName: chosen?.level.name ?? "") { sheet = nil }
      case .coverage:
        PlanCoverageView(
          store: plans, level: chosen?.level.slug ?? "",
          coverage: plans.coverage(forLevel: chosen?.level.slug ?? ""),
          currentRoom: chosen?.room.slug) { sheet = nil; plans.reload() }
      case .sessions:
        SessionListView(project: CaptureCoordinator.projectSlug) { sheet = nil }
      }
    }
  }

  /// The slug the store keys on, from whatever the owner typed in setup.
  /// The level and room a capture is for, once the house screen has chosen
  /// them. A named type rather than a tuple: the same reason ProjectDigest uses
  /// a struct to accumulate, and the reason a helper is never called `stat`.
  struct Choice {
    var level: LevelRef
    var room: SlugRef
  }

  private var unsupported: some View {
    VStack(spacing: 16) {
      Image(systemName: "xmark.circle").font(.largeTitle).foregroundStyle(.red)
      Text("This iPhone has no LiDAR scanner.").font(.headline)
      Text("VividHome needs one: an iPhone 15 Pro or newer.")
        .font(.footnote).foregroundStyle(.secondary)
      Text("build \(buildNumber)").font(.caption2).foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
    .padding()
  }

  private func finishing(_ message: String) -> some View {
    VStack(spacing: 16) {
      ProgressView()
      Text("Finalizing").font(.headline)
      Text(message).font(.footnote).foregroundStyle(.secondary)
      Text("This cannot be cancelled.").font(.caption2).foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
    .padding()
  }

  private func failure(_ message: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
      Text(message).multilineTextAlignment(.center)
      Button("Back") { coordinator.backToSetup() }.buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
