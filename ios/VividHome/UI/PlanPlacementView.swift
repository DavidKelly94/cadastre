import SwiftUI
import UIKit
import VividHomeCore

/// Placing a free capture on the plan after the fact (ADR-0031, design §6;
/// `phone-first-loop-design.md` §3).
///
/// A guided capture places itself before Stop. One captured without an
/// outline, or whose corners were never asked for, is placed here: the
/// capture's landmarks as chips, the drawing on the same canvas as Scale and
/// Outline, tap a chip then its place on the drawing, two pairs minimum. The
/// fit and its verdict show live with the HUD's thresholds, and *Place* writes
/// the same alignment file a guided capture writes, with `method: paired`.
struct PlanPlacementView: View {
  @ObservedObject var plans: PlanStore
  let layout: SessionLayout
  let manifest: Manifest?
  let project: String
  /// Told what was written, so the screen underneath shows it at once rather
  /// than on its next read.
  var onPlaced: (AlignmentFile) -> Void = { _ in }

  @State private var landmarks: [LandmarkRecord] = []
  /// Plan pixels, one per pair, in pairing order; `pairLabels` says whose.
  @State private var points: [CGPoint] = []
  @State private var pairLabels: [String] = []
  /// The landmark the next tap on the drawing places, when the owner chose
  /// one out of order.
  @State private var selected: String?
  @State private var existing: AlignmentFile?
  @State private var loaded = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  private var level: String { manifest?.level.slug ?? "" }
  private var plan: PlanFile? { plans.plans[level] }
  private var sessionID: String { layout.root.lastPathComponent }

  private var projectDirectory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("sessions", isDirectory: true)
      .appendingPathComponent(project, isDirectory: true)
  }

  /// Distinct labels, in tap order. Two landmarks with one label are one chip.
  private var labels: [String] {
    var seen = Set<String>()
    return landmarks.map(\.label).filter { seen.insert($0).inserted }
  }

  /// Whose place the next tap on the drawing sets.
  private var nextLabel: String? {
    if let selected, !pairLabels.contains(selected) { return selected }
    return labels.first { !pairLabels.contains($0) }
  }

  /// The fit the pairs so far give, with the HUD's thresholds.
  private var solution: PlanAlignment.Solution? {
    guard let plan, plan.isCalibrated else { return nil }
    var pairs: [PlanAlignment.Pair] = []
    for (label, point) in zip(pairLabels, points) {
      guard let landmark = landmarks.first(where: { $0.label == label }),
        let house = plan.planToHouse(u: Double(point.x), v: Double(point.y))
      else { continue }
      pairs.append(
        PlanAlignment.Pair(
          label: label, sessionXZ: (landmark.position.x, landmark.position.z), houseXZ: house))
    }
    guard pairs.count >= 2 else { return nil }
    // The landmark rule, as the guided capture uses it; the mesh route the PC
    // has is not on the phone.
    let floor = PlanAlignment.floorY(landmarks: landmarks.map { (kind: $0.kind, y: $0.position.y) })
    return PlanAlignment.solve(
      pairs: pairs, floorY: floor.y, floorSource: floor.source, floorHeight: plan.floorHeight)
  }

  private var canPlace: Bool {
    guard let solution else { return false }
    return solution.verdict != .notPlaced
  }

  var body: some View {
    Group {
      if let plan, plan.isCalibrated, let image = plans.image(for: plan) {
        if landmarks.isEmpty && loaded {
          ContentUnavailableView(
            "No landmarks in this capture", systemImage: "mappin.slash",
            description: Text("Nothing was tapped, so there is nothing to pair with the drawing. The PC can place it from markers or overlap later."))
        } else {
          VStack(spacing: 0) {
            header
            chips
            PlanPointCanvas(
              image: image, points: $points, maxPoints: nil, figure: .points,
              colour: { _ in .blue }, labels: pairLabels.map(Self.short))
            footer
          }
          .onChange(of: points.count) { _, count in tapped(count: count) }
        }
      } else if plan != nil {
        ContentUnavailableView(
          "This level's plan has no scale yet", systemImage: "ruler",
          description: Text("Set the scale on the plan screen first; a placement needs metres."))
      } else {
        ContentUnavailableView("No plan for this level", systemImage: "map")
      }
    }
    .navigationTitle("Place on the plan")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(existing == nil ? "Place" : "Replace", action: place).disabled(!canPlace)
      }
    }
    .onAppear(perform: load)
    .alert("Could not write the placement", isPresented: .constant(failure != nil)) {
      Button("OK") { failure = nil }
    } message: {
      Text(failure ?? "")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(nextLabel.map { "Tap where \(Self.short($0)) is on the drawing." }
        ?? "Every landmark paired. Drag a point under the loupe to fix it.")
        .font(.footnote.weight(.semibold))
      Text("Tap a chip to pair that landmark next, or a paired one to redo it. Pinch to zoom.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(.bar)
  }

  /// The capture's landmarks: the next one lit, paired ones ticked with their
  /// residual once there is a fit.
  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(labels, id: \.self) { label in
          let pairIndex = pairLabels.firstIndex(of: label)
          let next = nextLabel == label
          Button {
            if let pairIndex {
              points.remove(at: pairIndex)
              pairLabels.remove(at: pairIndex)
              selected = label
            } else {
              selected = label
            }
          } label: {
            HStack(spacing: 4) {
              if pairIndex != nil { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
              Text(Self.short(label)).font(.caption.weight(.semibold)).lineLimit(1)
              if let pairIndex, let solution, pairIndex < solution.residuals.count {
                Text("\(Int((solution.residuals[pairIndex] * 100).rounded())) cm")
                  .font(.caption2.monospacedDigit())
              }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
              next ? Color.accentColor : (pairIndex != nil ? Color.green.opacity(0.18) : Color(.tertiarySystemFill)),
              in: Capsule())
            .foregroundStyle(next ? Color.white : (pairIndex != nil ? Color.green : Color.primary))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 8)
    }
    .background(.bar)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let solution {
        Label(solution.summary, systemImage: solution.verdict == .placed
          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(solution.verdict == .placed ? Color.green
            : (solution.verdict == .check ? Color.orange : Color.red))
      } else {
        Text("Two pairs are the minimum; a third shows whether they agree.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let existing {
        Text("Already placed (\(existing.method), \(Int((existing.rmsM * 100).rounded())) cm). Replace overwrites it.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Place writes the placement beside the plans; the PC adopts it with the capture.")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("Undo last") { _ = points.popLast() }
          .font(.footnote).disabled(points.isEmpty)
        Spacer()
        Button("Start again") { points = [] }
          .font(.footnote).disabled(points.isEmpty)
      }
    }
    .padding(16)
    .background(.bar)
  }

  // MARK: - Behaviour

  /// The canvas appends a point per tap and removes one per undo; this keeps
  /// the labels in step and says which landmark a new point is for.
  private func tapped(count: Int) {
    guard count > pairLabels.count else {
      pairLabels = Array(pairLabels.prefix(count))
      return
    }
    guard let label = nextLabel else {
      points.removeLast()
      return
    }
    pairLabels.append(label)
    selected = nil
  }

  private func load() {
    guard !loaded else { return }
    loaded = true
    landmarks = JSONLReader.records(LandmarkRecord.self, in: layout.landmarks)
    existing = AlignmentFile.read(at: AlignmentFile.url(projectDirectory: projectDirectory, sessionID: sessionID))
    // An existing placement comes up as its pairs, so it can be adjusted
    // rather than redone from nothing.
    guard let existing, let plan else { return }
    for pair in existing.pairs where pair.houseXZ.count == 2 {
      guard landmarks.contains(where: { $0.label == pair.label }), !pairLabels.contains(pair.label),
        let pixel = plan.houseToPlan(x: pair.houseXZ[0], z: pair.houseXZ[1])
      else { continue }
      points.append(CGPoint(x: pixel.u, y: pixel.v))
      pairLabels.append(pair.label)
    }
  }

  private func place() {
    guard let solution else { return }
    let file = AlignmentFile(sessionID: sessionID, level: level, solution: solution, method: "paired")
    do {
      try file.write(to: AlignmentFile.url(projectDirectory: projectDirectory, sessionID: sessionID))
      existing = file
      onPlaced(file)
      dismiss()
    } catch {
      failure = error.localizedDescription
    }
  }

  /// `corner-ne2` as `NE2`; a typed label as itself.
  static func short(_ label: String) -> String {
    label.hasPrefix("corner-") ? String(label.dropFirst("corner-".count)).uppercased() : label
  }
}
