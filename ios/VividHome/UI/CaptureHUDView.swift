import ARKit
import Combine
import SwiftUI
import VividHomeCore

/// The capture HUD.
///
/// Laid out from the design canvas: a status strip across the top, a marker and
/// landmark strip, and the controls in the bottom third where a thumb reaches.
/// Every number on it is a real published value from the recorder, not a
/// placeholder.
///
/// One thing the canvas could not settle and this does not either: the scrim is
/// a fixed 72% because nothing here samples the camera feed to know when the
/// scene behind it is bright. The brief calls for 88% over a bright scene, and
/// until that is measured on a device, chrome over a sunlit opening is the case
/// most likely to be unreadable.
struct CaptureHUDView: View {
  @ObservedObject var coordinator: CaptureCoordinator
  @ObservedObject var controller: ARSessionController
  @ObservedObject var recorder: SessionRecorder

  @State private var landmarkKind: LandmarkKind = .corner
  @State private var flash: String?

  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    ZStack {
      ARViewContainer(coordinator: coordinator, onTap: handleTap)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        statusStrip
        markerStrip
        Spacer()
        if let flash { flashBanner(flash) }
        if case .warn(let message) = recorder.verdict { banner(message, tone: Tokens.warn) }
        controls
      }
    }
    .onReceive(tick) { _ in coordinator.refreshFreeSpace() }
    .onChange(of: recorder.verdict) { _, verdict in
      // The recorder decides to stop; the screen only carries the reason out.
      if case .stop(let reason) = verdict { coordinator.stop(reason: reason) }
    }
  }

  // MARK: - Top

  private var statusStrip: some View {
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        Circle().fill(trackingColour).frame(width: 10, height: 10)
        Text(trackingWord).font(.caption.weight(.bold)).foregroundStyle(Tokens.ink)
        Spacer()
        Text(elapsedText).font(.caption.monospacedDigit()).foregroundStyle(Tokens.ink)
      }
      HStack(spacing: 14) {
        stat("KF", "\(recorder.stats.keyframes)")
        stat("DROP", "\(recorder.stats.dropped)", tone: recorder.stats.dropped > 0 ? Tokens.warn : nil)
        stat("STILL", "\(recorder.stats.stills)")
        stat("MRK", "\(recorder.stats.markerObservations)")
        stat("LM", "\(coordinator.landmarkCount)")
        Spacer()
        stat("FREE", freeText, tone: coordinator.freeBytes < 2_000_000_000 ? Tokens.warn : nil)
        stat("THERM", thermalWord, tone: thermalColour)
      }
      if let reasonText {
        Text(reasonText).font(.caption2).foregroundStyle(Tokens.warn)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Tokens.scrim)
    .overlay(alignment: .bottom) { Rectangle().fill(Tokens.hairline).frame(height: 1) }
  }

  private var markerStrip: some View {
    HStack(spacing: 8) {
      Text(coordinator.contextLabel).font(.caption2).foregroundStyle(Tokens.inkSecondary)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(coordinator.markersSeen, id: \.self) { id in
            Text(id)
              .font(.caption2.monospaced())
              .padding(.horizontal, 8).padding(.vertical, 4)
              .background(Tokens.ok.opacity(0.22), in: Capsule())
              .foregroundStyle(Tokens.ok)
          }
          if coordinator.markersSeen.isEmpty {
            Text("no markers seen").font(.caption2).foregroundStyle(Tokens.inkSecondary)
          }
        }
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 6)
    .background(Tokens.scrim)
  }

  // MARK: - Bottom

  private var controls: some View {
    VStack(spacing: 12) {
      // Landmark kind sits above the buttons so a tap on the feed always means
      // the same thing; a mode that changed under you mid-sweep would put a
      // door where a corner belongs and nothing downstream could tell.
      Picker("Landmark", selection: $landmarkKind) {
        Text("Corner").tag(LandmarkKind.corner)
        Text("Door").tag(LandmarkKind.door)
        Text("Window").tag(LandmarkKind.window)
        Text("Floor").tag(LandmarkKind.floor)
      }
      .pickerStyle(.segmented)

      HStack(spacing: 20) {
        Button {
          coordinator.setShowMesh(!coordinator.showMesh)
        } label: {
          Label("Mesh", systemImage: coordinator.showMesh ? "square.grid.3x3.fill" : "square.grid.3x3")
            .labelStyle(.iconOnly).font(.title3)
        }
        .foregroundStyle(coordinator.showMesh ? Tokens.accentCool : Tokens.inkSecondary)

        Spacer()

        Button { coordinator.stop() } label: {
          Text("STOP")
            .font(.headline.weight(.heavy))
            .foregroundStyle(Tokens.onAccentWarm)
            .frame(width: 84, height: 84)
            .background(Tokens.accentWarm, in: Circle())
        }

        Spacer()

        Button { coordinator.takeStill() } label: {
          Label("Still", systemImage: "camera").labelStyle(.iconOnly).font(.title3)
        }
        .foregroundStyle(Tokens.ink)
      }
      Text("Tap the view to mark a \(landmarkKind.rawValue)")
        .font(.caption2).foregroundStyle(Tokens.inkSecondary)
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 28)
    .background(Tokens.scrim)
  }

  private func banner(_ text: String, tone: Color) -> some View {
    Text(text)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(Tokens.onAccentWarm)
      .padding(.horizontal, 14).padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .background(tone)
  }

  private func flashBanner(_ text: String) -> some View {
    banner(text, tone: Tokens.accentCool)
  }

  // MARK: - Interaction

  private func handleTap(_ point: CGPoint) {
    let label = "\(landmarkKind.rawValue)-\(coordinator.landmarkCount + 1)"
    let ok = coordinator.markLandmark(at: point, label: label, kind: landmarkKind)
    show(ok ? "Marked \(label)" : "No surface there — aim at a wall or floor")
  }

  private func show(_ text: String) {
    flash = text
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      if flash == text { flash = nil }
    }
  }

  // MARK: - Formatting

  private var trackingColour: Color {
    switch controller.status.tracking {
    case .normal: return Tokens.ok
    case .limited: return Tokens.warn
    case .notAvailable: return Tokens.error
    }
  }

  private var trackingWord: String {
    switch controller.status.tracking {
    case .normal: return "OK"
    case .limited: return "LIMITED"
    case .notAvailable: return "NO TRACKING"
    }
  }

  private var reasonText: String? {
    switch controller.status.reason {
    case .none: return nil
    case .initializing: return "Starting tracking — move the phone slowly."
    case .excessiveMotion: return "Moving too fast. Slow the sweep down."
    case .insufficientFeatures: return "Not enough detail here. Try a textured surface."
    case .relocalizing: return "Finding the room again. Return to where you started."
    }
  }

  private var thermalWord: String { controller.status.thermal.rawValue }

  private var thermalColour: Color? {
    switch controller.status.thermal {
    case .nominal, .fair: return nil
    case .serious: return Tokens.warn
    case .critical: return Tokens.error
    }
  }

  private var elapsedText: String {
    let total = Int(recorder.elapsed)
    return String(format: "%02d:%02d", total / 60, total % 60)
  }

  private var freeText: String {
    let gb = Double(coordinator.freeBytes) / 1_000_000_000
    return gb >= 10 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
  }

  private func stat(_ label: String, _ value: String, tone: Color? = nil) -> some View {
    HStack(spacing: 4) {
      Text(label).font(.caption2).foregroundStyle(Tokens.inkSecondary)
      Text(value).font(.caption2.monospacedDigit().weight(.semibold))
        .foregroundStyle(tone ?? Tokens.ink)
    }
  }
}

/// Hosts the `ARSCNView` and reports taps in view coordinates, which is what a
/// raycast needs.
struct ARViewContainer: UIViewRepresentable {
  let coordinator: CaptureCoordinator
  let onTap: (CGPoint) -> Void

  func makeUIView(context: Context) -> ARSCNView {
    let view = ARSCNView(frame: .zero)
    coordinator.attach(view: view)
    let recognizer = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Tapper.handle(_:)))
    view.addGestureRecognizer(recognizer)
    return view
  }

  func updateUIView(_ uiView: ARSCNView, context: Context) {
    context.coordinator.onTap = onTap
  }

  func makeCoordinator() -> Tapper { Tapper(onTap: onTap) }

  final class Tapper: NSObject {
    var onTap: (CGPoint) -> Void
    init(onTap: @escaping (CGPoint) -> Void) { self.onTap = onTap }

    @objc func handle(_ recognizer: UITapGestureRecognizer) {
      guard let view = recognizer.view else { return }
      onTap(recognizer.location(in: view))
    }
  }
}
