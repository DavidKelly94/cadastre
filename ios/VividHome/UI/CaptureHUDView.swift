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
  @State private var renaming = false
  @State private var draftLabel = ""
  /// In a guided room the corner chips replace the kind picker; this brings
  /// the picker back for a door or a window.
  @State private var otherMarks = false
  /// The plan inset can be folded away when it is in the way of the picture.
  @State private var showInset = true
  @State private var camera: (x: Double, z: Double)?

  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    ZStack {
      ARViewContainer(coordinator: coordinator, onTap: handleTap)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        statusStrip
        markerStrip
        if let room = coordinator.guidedRoom, let guidance = coordinator.guidance {
          HStack(alignment: .top) {
            if showInset {
              PlanInsetView(
                room: room, guidance: guidance, placement: coordinator.placement,
                coverage: coordinator.coverage, walk: coordinator.walk, priorWalks: coordinator.priorWalks,
                landmarks: coordinator.landmarks, camera: camera)
            }
            Button {
              showInset.toggle()
            } label: {
              Image(systemName: showInset ? "chevron.left.circle.fill" : "map.circle.fill")
                .font(.title3)
            }
            .foregroundStyle(Tokens.inkSecondary)
            .accessibilityLabel(showInset ? "Hide the plan" : "Show the plan")
            Spacer()
          }
          .padding(.horizontal, 12).padding(.top, 8)
        }
        Spacer()
        if let flash { flashBanner(flash) }
        if case .warn(let message) = recorder.verdict { banner(message, tone: Tokens.warn) }
        if selected != nil { selectionBar }
        controls
      }
    }
    .onReceive(tick) { _ in
      coordinator.refreshFreeSpace()
      camera = coordinator.cameraXZ()
    }
    .onChange(of: recorder.verdict) { _, verdict in
      // The recorder decides to stop; the screen only carries the reason out.
      if case .stop(let reason) = verdict { coordinator.stop(reason: reason) }
    }
    .alert("Rename landmark", isPresented: $renaming) {
      TextField("Label", text: $draftLabel)
      Button("Cancel", role: .cancel) {}
      Button("Save") { coordinator.renameSelectedLandmark(to: draftLabel) }
    } message: {
      Text("Use something you will recognise on the plan: \"kitchen NW corner\".")
    }
    .onChange(of: renaming) { _, showing in
      if showing { draftLabel = selected?.label ?? "" }
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
        readout("KF", "\(recorder.stats.keyframes)")
        readout("DROP", "\(recorder.stats.dropped)", tone: recorder.stats.dropped > 0 ? Tokens.warn : nil)
        readout("STILL", "\(recorder.stats.stills)")
        readout("MRK", "\(recorder.stats.markerObservations)")
        if let placement = coordinator.placement {
          // Placed live against the outline (ADR-0031): the residual, not a
          // geometry word, because the plan is now part of the fit.
          readout("FIT", "\(Int((placement.rms * 100).rounded())) cm", tone: placement.hudColour)
        } else {
          readout("FIT", coordinator.alignment.verdict.hudWord, tone: coordinator.alignment.hudColour)
        }
        Spacer()
        readout("FREE", freeText, tone: coordinator.freeBytes < 2_000_000_000 ? Tokens.warn : nil)
        readout("THERM", thermalWord, tone: thermalColour)
      }
      if let reasonText {
        Text(reasonText).font(.caption2).foregroundStyle(Tokens.warn)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if reasonText == nil, let placement = coordinator.placement {
        Text(placement.summary).font(.caption2).foregroundStyle(placement.hudColour)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if reasonText == nil, let advice = coordinator.alignment.advice {
        // Tracking trouble outranks it: a limited-tracking frame is worth fixing
        // before the next landmark is worth placing.
        Text(advice).font(.caption2).foregroundStyle(Tokens.accentCool)
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

  // MARK: - Selection

  private var selected: PlacedLandmark? {
    coordinator.landmarks.first { $0.id == coordinator.selectedLandmark }
  }

  /// Shown only while a landmark is selected, so the controls below it keep the
  /// same positions at all other times — a button that moves under a thumb
  /// mid-sweep is worse than one that is occasionally absent.
  private var selectionBar: some View {
    HStack(spacing: 12) {
      Circle().fill(Color.white).frame(width: 10, height: 10)
      Text(selected?.label ?? "")
        .font(.footnote.weight(.semibold)).foregroundStyle(Tokens.ink)
        .lineLimit(1)
      Spacer()
      if selected?.isSnapped == true {
        Button("Unsnap") { coordinator.unsnapSelectedLandmark() }
          .font(.footnote).foregroundStyle(Tokens.accentCool)
      }
      Button("Rename") { renaming = true }
        .font(.footnote).foregroundStyle(Tokens.accentCool)
      Button("Delete") { coordinator.deleteSelectedLandmark() }
        .font(.footnote.weight(.semibold)).foregroundStyle(Tokens.error)
      Button("Done") { coordinator.selectedLandmark = nil }
        .font(.footnote).foregroundStyle(Tokens.inkSecondary)
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(Tokens.raised)
    .overlay(alignment: .top) { Rectangle().fill(Tokens.hairline).frame(height: 1) }
  }

  // MARK: - Bottom

  private var controls: some View {
    VStack(spacing: 12) {
      // Landmark kind sits above the buttons so a tap on the feed always means
      // the same thing; a mode that changed under you mid-sweep would put a
      // door where a corner belongs and nothing downstream could tell. In a
      // guided room (ADR-0031) the corners to tap take its place, by name.
      if let guidance = coordinator.guidance, !otherMarks {
        cornerChips(guidance)
      } else {
        Picker("Landmark", selection: $landmarkKind) {
          Text("Corner").tag(LandmarkKind.corner)
          Text("Door").tag(LandmarkKind.door)
          Text("Window").tag(LandmarkKind.window)
          Text("Floor").tag(LandmarkKind.floor)
        }
        .pickerStyle(.segmented)
        if coordinator.guidance != nil {
          Button("Back to the corners") {
            otherMarks = false
            landmarkKind = .corner
          }
          .font(.caption2).foregroundStyle(Tokens.accentCool)
        }
      }

      if !coordinator.checklist.isEmpty { checklistChips }

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

        Button { takeStill(item: nil, named: nil) } label: {
          Label("Still", systemImage: "camera").labelStyle(.iconOnly).font(.title3)
        }
        .foregroundStyle(Tokens.ink)
      }
      Text(hint)
        .font(.caption2).foregroundStyle(Tokens.inkSecondary)
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 28)
    .background(Tokens.scrim)
  }

  private var hint: String {
    if coordinator.selectedLandmark != nil { return "Tap where it should be" }
    if let guidance = coordinator.guidance, !otherMarks {
      if let next = guidance.next {
        return "Stand at the \(Self.short(next)) corner and tap the floor where the walls meet"
      }
      return guidance.remaining == 0 && guidance.skipped.isEmpty
        ? "Every corner tapped · tap a mark to edit it"
        : "Tap a skipped corner to ask for it again · tap a mark to edit it"
    }
    return "Tap the view to mark a \(landmarkKind.rawValue) · tap a mark to edit it"
  }

  /// The room's corners by name, in outline order: the next one lit, the
  /// placed ones ticked, the skipped ones dimmed and tappable to ask again.
  private func cornerChips(_ guidance: CaptureCoordinator.Guidance) -> some View {
    HStack(spacing: 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(guidance.corners, id: \.self) { corner in
            let placed = guidance.placed.contains(corner)
            let skipped = guidance.skipped.contains(corner)
            let next = guidance.next == corner
            Button {
              if !placed { coordinator.chooseCorner(corner) }
            } label: {
              HStack(spacing: 4) {
                if placed { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                Text(Self.short(corner))
                  .font(.caption.weight(.semibold))
                  .strikethrough(skipped)
              }
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(
                next ? Tokens.accentCool : (placed ? Tokens.ok.opacity(0.22) : Tokens.raised),
                in: Capsule())
              .foregroundStyle(next ? Tokens.onAccentWarm : (placed ? Tokens.ok : (skipped ? Tokens.inkSecondary : Tokens.ink)))
            }
            .buttonStyle(.plain)
          }
        }
      }
      if guidance.next != nil {
        Button("Skip") { coordinator.skipNextCorner() }
          .font(.caption.weight(.semibold)).foregroundStyle(Tokens.inkSecondary)
      }
      Button {
        otherMarks = true
      } label: {
        Image(systemName: "ellipsis.circle").font(.title3)
      }
      .foregroundStyle(Tokens.inkSecondary)
      .accessibilityLabel("Other marks")
    }
  }

  /// The stills the pass's trades require (ADR-0031, design §5), ticked as
  /// they are taken. A chip takes a still for that item, one tap, so the list
  /// is both the reminder and the shutter; the camera button takes a still
  /// with no label, which ticks nothing.
  private var checklistChips: some View {
    let taken = Set(coordinator.stillsTaken.compactMap { $0 })
    let done = coordinator.checklist.filter { taken.contains($0.id) }.count
    return HStack(spacing: 8) {
      Text("STILLS \(done)/\(coordinator.checklist.count)")
        .font(.caption2.weight(.bold)).foregroundStyle(Tokens.inkSecondary)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(coordinator.checklist) { item in
            let ticked = taken.contains(item.id)
            Button {
              takeStill(item: item.id, named: item.name)
            } label: {
              HStack(spacing: 4) {
                Image(systemName: ticked ? "checkmark" : "camera").font(.caption2.weight(.bold))
                Text(item.name).font(.caption.weight(.semibold)).lineLimit(1)
              }
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(ticked ? Tokens.ok.opacity(0.22) : Tokens.raised, in: Capsule())
              .foregroundStyle(ticked ? Tokens.ok : Tokens.ink)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func takeStill(item: String?, named name: String?) {
    if coordinator.takeStill(item: item) {
      if let name { show("Still: \(name)") }
    } else {
      show("Hold on — the last still is still being written")
    }
  }

  /// `corner-ne2` as `NE2`.
  private static func short(_ label: String) -> String {
    label.replacingOccurrences(of: "corner-", with: "").uppercased()
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
    switch coordinator.handleTap(at: point, kind: landmarkKind) {
    case .placed(let label):
      show("Marked \(label)")
    case .snapped(let label, let moved):
      show("Marked \(label) · snapped to the corner, \(Int((moved * 100).rounded())) cm")
    case .selected(let label):
      show("\(label) selected — tap where it should be")
    case .moved(let label):
      show("Moved \(label)")
    case .noSurface:
      show("No surface there — aim at a wall or floor")
    case .ignored:
      break
    }
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

  /// Named `readout` rather than `stat`: `stat` is a struct in Darwin, so any
  /// call-site mistake here resolves to that instead and the compiler reports
  /// a POSIX type rather than the argument you got wrong.
  private func readout(_ label: String, _ value: String, tone: Color? = nil) -> some View {
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

extension AlignmentQuality.Verdict {
  /// Four characters, because the strip is tight and these sit beside monospaced
  /// counts.
  var hudWord: String {
    switch self {
    case .impossible: return "NONE"
    case .weak: return "WEAK"
    case .good: return "OK"
    }
  }
}

extension PlanAlignment.Solution {
  var hudColour: Color {
    switch verdict {
    case .placed: return Tokens.ok
    case .check: return Tokens.warn
    case .notPlaced: return Tokens.error
    }
  }
}

extension AlignmentQuality.Report {
  var hudColour: Color {
    switch verdict {
    case .impossible: return Tokens.error
    case .weak: return Tokens.warn
    case .good: return Tokens.ok
    }
  }
}
