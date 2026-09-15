import ARKit
import SwiftUI
import VividHomeCore

/// The app's one route, for now.
///
/// Setup, capture, review. The designed Project, Level and Room screens sit
/// above this and do not exist yet; when they do, they choose the level and room
/// and this becomes the leaf rather than the whole app.
struct ContentView: View {
  @StateObject private var coordinator = CaptureCoordinator()
  @StateObject private var plans = PlanStore(project: CaptureCoordinator.projectSlug)
  @State private var sheet: Sheet?
  @State private var levelName = "Level 1"
  @State private var roomName = ""

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
          CaptureSetupView(
            coordinator: coordinator,
            plans: plans,
            levelName: $levelName,
            roomName: $roomName,
            onAddPlan: { sheet = .importPlan },
            onShowCoverage: { sheet = .coverage },
            onShowSessions: { sheet = .sessions })
        case .recording:
          CaptureHUDView(
            coordinator: coordinator,
            controller: coordinator.controller,
            recorder: coordinator.recorder)
        case .finishing(let message):
          finishing(message)
        case .review(let summary):
          SessionReviewView(summary: summary) { coordinator.backToSetup() }
        case .failed(let message):
          failure(message)
        }
      }
    }
    .sheet(item: $sheet) { which in
      switch which {
      case .importPlan:
        PlanImportView(store: plans, levelName: levelName) { sheet = nil }
      case .coverage:
        PlanCoverageView(
          store: plans, level: levelSlug,
          coverage: plans.coverage(forLevel: levelSlug),
          currentRoom: roomSlug) { sheet = nil; plans.reload() }
      case .sessions:
        SessionListView(project: CaptureCoordinator.projectSlug) { sheet = nil }
      }
    }
  }

  /// The slug the store keys on, from whatever the owner typed in setup.
  private var levelSlug: String { SessionID.slug(levelName) ?? "l1" }
  private var roomSlug: String? { SessionID.slug(roomName) }

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
