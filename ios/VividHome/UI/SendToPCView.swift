import SwiftUI
import VividHomeCore

/// Sending captures to the PC: what will go, over what, and how it went.
///
/// The sheet exists so the owner can watch a long send and so a send over
/// cellular is a decision rather than a surprise. It is the same sheet for one
/// capture and for a whole visit.
struct SendToPCView: View {
  let rows: [SessionListView.Row]
  @ObservedObject var link: PCLink
  /// Runs once the sheet is dismissed after a send, so the list can ask the
  /// PC again and refresh its marks.
  let onFinished: () -> Void

  @StateObject private var uploader = SessionUploader()
  @State private var expensive: Bool?
  /// What will actually go over the wire: the captures plus the plan files
  /// beside them, listed the way the send lists them. Until that is counted,
  /// the rows' own sizes stand in. The first walk showed 49 MB and then sent
  /// 53 MB because only the second figure counted the plan.
  @State private var exactBytes: Int?
  @Environment(\.dismiss) private var dismiss

  private var totalBytes: Int { exactBytes ?? rows.reduce(0) { $0 + $1.bytes } }

  var body: some View {
    NavigationStack {
      List {
        Section {
          LabeledContent("To", value: link.baseURL?.host ?? "no PC address")
          LabeledContent(
            "Sending",
            value: "\(rows.count) capture\(rows.count == 1 ? "" : "s") · \(SessionListView.bytes(totalBytes))")
        } footer: {
          Text(networkNote)
        }

        if uploader.running || uploader.finished {
          Section {
            ProgressView(value: Double(uploader.sentBytes), total: Double(max(uploader.totalBytes, 1)))
            Text(
              "\(SessionListView.bytes(uploader.sentBytes)) of "
                + "\(SessionListView.bytes(uploader.totalBytes))")
              .font(.footnote).foregroundStyle(.secondary)
            if let why = uploader.stoppedBecause {
              Label(why, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
            }
          } header: {
            Text(uploader.running ? "Sending" : "Sent")
          }
          Section("Captures") {
            ForEach(uploader.items) { item in
              itemRow(item)
            }
          }
        } else if !link.canSend {
          Section {
            Text(
              "Type the PC's address and the pairing code under PC on the project screen first. "
                + "`vividhome serve --lan` prints both.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Send to the PC")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if uploader.running {
            Button("Stop") { uploader.cancel() }
          } else {
            Button(uploader.finished ? "Done" : "Cancel") {
              dismiss()
              if uploader.finished { onFinished() }
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if !uploader.running && !uploader.finished {
          sendBar
        }
      }
      .task { expensive = await SessionUploader.pathIsExpensive() }
      .task {
        let jobs = jobs
        exactBytes = await Task.detached {
          jobs.reduce(0) { total, job in
            let files =
              (try? SessionUpload.files(of: job.layout, plans: job.plans, alignments: job.alignments)) ?? []
            return total + SessionUpload.totalBytes(files)
          }
        }.value
      }
      .interactiveDismissDisabled(uploader.running)
    }
  }

  private var sendBar: some View {
    VStack(spacing: 8) {
      if expensive == true {
        Label(
          "This phone is on cellular or a hotspot. \(SessionListView.bytes(totalBytes)) will count "
            + "against your data.",
          systemImage: "antenna.radiowaves.left.and.right")
          .font(.footnote).foregroundStyle(.orange)
      }
      Button {
        guard let base = link.baseURL else { return }
        uploader.start(jobs, to: base, code: link.pairingCode)
      } label: {
        Label(
          expensive == true ? "Send over cellular anyway" : "Send",
          systemImage: "arrow.up.to.line")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!link.canSend || rows.isEmpty)
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(.bar)
  }

  private var jobs: [SessionUploader.Job] {
    rows.map { row in
      SessionUploader.Job(
        layout: row.layout,
        name: row.manifest?.room.name ?? row.id,
        plans: row.layout.root.deletingLastPathComponent()
          .appendingPathComponent("plans", isDirectory: true),
        alignments: row.layout.root.deletingLastPathComponent()
          .appendingPathComponent("alignments", isDirectory: true))
    }
  }

  private var networkNote: String {
    switch expensive {
    case true?:
      return "Each file goes on its own, so a send that drops resumes from where it stopped."
    case false?:
      return "On Wi-Fi. Each file goes on its own, so a send that drops resumes from where it stopped."
    case nil:
      return "Checking which network this phone is on."
    }
  }

  @ViewBuilder
  private func itemRow(_ item: SessionUploader.Item) -> some View {
    HStack(alignment: .top, spacing: 10) {
      switch item.state {
      case .waiting:
        Image(systemName: "circle.dotted").foregroundStyle(.secondary)
      case .sending:
        ProgressView().controlSize(.small)
      case .skipped:
        Image(systemName: "minus.circle").foregroundStyle(.secondary)
      case .ingested(let validated, _):
        Image(systemName: validated ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
          .foregroundStyle(validated ? .green : .orange)
      case .failed:
        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(item.name).font(.body)
        Text(note(for: item.state)).font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private func note(for state: SessionUploader.Item.State) -> String {
    switch state {
    case .waiting: return "Waiting"
    case .sending: return "Sending"
    case .skipped(let why): return why
    case .ingested(_, let note): return note
    case .failed(let why): return why
    }
  }
}
