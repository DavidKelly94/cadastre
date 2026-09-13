import ARKit
import CadastreCore
import SwiftUI

/// First-run screen: confirms the build on the device and that this phone can do
/// scene reconstruction, and opens a bare AR session so the camera path is proven
/// end to end before any capture logic exists.
struct ContentView: View {
  @State private var showingARView = false

  private var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
  }

  private var supportsSceneReconstruction: Bool {
    ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
  }

  var body: some View {
    VStack(spacing: 24) {
      Text("Cadastre build \(buildNumber)")
        .font(.title2.weight(.semibold))

      Label(
        supportsSceneReconstruction
          ? "Scene reconstruction supported"
          : "Scene reconstruction unavailable",
        systemImage: supportsSceneReconstruction ? "checkmark.circle" : "xmark.circle"
      )
      .foregroundStyle(supportsSceneReconstruction ? .green : .red)

      Text("core \(CadastreCore.version) · session format v\(CadastreCore.sessionFormatVersion)")
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button("Open AR session") {
        showingARView = true
      }
      .buttonStyle(.borderedProminent)
      .disabled(!supportsSceneReconstruction)
    }
    .padding()
    .fullScreenCover(isPresented: $showingARView) {
      ARSessionView()
    }
  }
}

#Preview {
  ContentView()
}
