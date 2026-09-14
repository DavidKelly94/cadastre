import ARKit
import SwiftUI

/// Full-screen AR session. Deliberately thin: it starts a world-tracking session
/// with scene reconstruction and shows it. Anything testable belongs in
/// VividHomeCore, not here.
struct ARSessionView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack(alignment: .topTrailing) {
      ARSessionViewRepresentable()
        .ignoresSafeArea()

      Button("Done") {
        dismiss()
      }
      .buttonStyle(.borderedProminent)
      .padding()
    }
  }
}

private struct ARSessionViewRepresentable: UIViewRepresentable {
  func makeUIView(context: Context) -> ARSCNView {
    let view = ARSCNView(frame: .zero)
    view.session.run(Self.configuration())
    return view
  }

  func updateUIView(_ uiView: ARSCNView, context: Context) {}

  static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
    uiView.session.pause()
  }

  private static func configuration() -> ARWorldTrackingConfiguration {
    let configuration = ARWorldTrackingConfiguration()
    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
      configuration.sceneReconstruction = .meshWithClassification
    }
    if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
      configuration.frameSemantics.insert(.sceneDepth)
    }
    configuration.planeDetection = [.horizontal, .vertical]
    return configuration
  }
}
