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
          CaptureSetupView(coordinator: coordinator)
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
