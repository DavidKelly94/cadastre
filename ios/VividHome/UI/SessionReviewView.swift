import SwiftUI
import VividHomeCore

/// What was actually saved, shown once the session is closed.
///
/// The numbers come from the finalised manifest rather than the live recorder,
/// so they cannot drift while this is on screen. There is no trajectory plot
/// yet — that is the designed screen's centrepiece and it needs the plan work
/// from ADR-0025 to be worth drawing.
struct SessionReviewView: View {
  let summary: CaptureCoordinator.SessionSummary
  let onDone: () -> Void

  var body: some View {
    NavigationStack {
      List {
        if let reason = summary.stoppedBecause {
          Section {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(Tokens.warn)
          } header: {
            Text("Stopped early")
          }
        }

        Section("Capture") {
          row("Room", summary.room)
          row("Level", summary.level)
          row("Trades", summary.phases.map(\.displayName).joined(separator: ", "))
          row("Duration", duration)
          row("Session", summary.sessionID, mono: true)
        }

        Section("Recorded") {
          row("Keyframes", "\(summary.stats.keyframes)")
          row("Dropped", "\(summary.stats.dropped)", tone: summary.stats.dropped > 0 ? .orange : nil)
          row("Stills", "\(summary.stats.stills)")
          row("Marker sightings", "\(summary.stats.markerObservations)")
          row("Landmarks", "\(summary.stats.landmarks)")
          row("On disk", bytes(summary.stats.bytes))
        }

        if let mesh = summary.mesh {
          Section("Mesh") {
            row("Anchors", "\(mesh.anchors)")
            row("Vertices", "\(mesh.vertices)")
            row("Faces", "\(mesh.faces)")
          }
        }

        Section {
          if summary.landmarkLabels.isEmpty {
            Text("None.").font(.footnote).foregroundStyle(.secondary)
          } else {
            ForEach(summary.landmarkLabels, id: \.self) { label in
              Text(label).font(.footnote.monospaced())
            }
          }
        } header: {
          Text("Landmarks placed")
        } footer: {
          Text("These labels are what you pair with points on the floor plan. "
            + "If one would not tell you which corner it is, rename it before the next capture.")
        }

        Section("Markers seen") {
          if summary.markersSeen.isEmpty {
            Text("None, which is normal. Markers are optional — this capture is placed "
              + "on the plan through its landmarks (ADR-0026).")
              .font(.footnote).foregroundStyle(.secondary)
          } else {
            Text(summary.markersSeen.joined(separator: "  ")).font(.body.monospaced())
          }
        }

        Section {
          // Quality flags the owner can act on now, while still in the room.
          if summary.stats.keyframes == 0 {
            flag("No keyframes were written. Nothing here is usable.", bad: true)
          }
          if summary.stats.trackingLimited > summary.duration * 0.25, summary.duration > 0 {
            flag("Tracking was limited for a quarter of the session. Consider recapturing.", bad: true)
          }
          // Landmarks are the alignment input now that markers are optional
          // (ADR-0026). Under three and `align` either refuses or fits with no
          // residual worth reading, and nothing can rescue the session later.
          if summary.stats.landmarks == 0 {
            flag(
              "No landmarks. This capture cannot be placed on the plan, and nothing "
                + "downstream can fix that.", bad: true)
          } else if summary.stats.landmarks < 3 {
            flag(
              "Only \(summary.stats.landmarks) landmark\(summary.stats.landmarks == 1 ? "" : "s"). "
                + "Alignment needs two and cannot be checked under three — tap the room corners.",
              bad: true)
          }
        } header: {
          Text("Checks")
        } footer: {
          Text("Copy the folder to the PC and run `vividhome validate` before deleting it here.")
        }

        Section {
          ShareLink(item: summary.root) {
            Label("Share session folder", systemImage: "square.and.arrow.up")
          }
        }
      }
      .navigationTitle("Capture saved")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
    }
  }

  private func row(_ label: String, _ value: String, mono: Bool = false, tone: Color? = nil)
    -> some View
  {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(mono ? .footnote.monospaced() : .body)
        .foregroundStyle(tone ?? .primary)
        .multilineTextAlignment(.trailing)
    }
  }

  private func flag(_ text: String, bad: Bool) -> some View {
    Label(text, systemImage: bad ? "xmark.octagon.fill" : "exclamationmark.circle")
      .foregroundStyle(bad ? .red : .orange)
      .font(.footnote)
  }

  private var duration: String {
    let total = Int(summary.duration)
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  private func bytes(_ value: Int) -> String {
    let mb = Double(value) / 1_000_000
    return mb >= 1000 ? String(format: "%.2f GB", mb / 1000) : String(format: "%.0f MB", mb)
  }
}
