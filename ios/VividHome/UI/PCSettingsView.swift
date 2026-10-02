import SwiftUI
import VividHomeCore

/// Where the PC is, and whether it answers.
///
/// The Test button is the honest part: "the PC is off", "the phone is on
/// cellular" and "the router isolates guests" all look the same from here, and
/// the text under the button has to help the owner tell them apart.
struct PCSettingsView: View {
  @ObservedObject var link: PCLink
  let onDone: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if link.discovered.isEmpty {
            Text("Looking on this network. The PC has to be on, on this Wi-Fi, and running "
              + "`vividhome serve --lan`; and iOS has to allow this app on the local network "
              + "(Settings → Privacy & Security → Local Network).")
              .font(.footnote).foregroundStyle(.secondary)
          }
          ForEach(link.discovered) { item in
            Button {
              link.use(item)
            } label: {
              HStack {
                Text(item.name)
                Spacer()
                Text(item.url?.host ?? "resolving")
                  .font(.footnote).foregroundStyle(.secondary)
              }
            }
            .disabled(item.url == nil)
          }
        } header: {
          Text("Found on this network")
        }

        Section {
          // No URL in the placeholder: iOS styles one as a link, which the
          // first walk read as something to tap.
          TextField("PC address", text: $link.addressText)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button {
            Task { await link.test() }
          } label: {
            if link.testing {
              ProgressView()
            } else {
              Text("Test")
            }
          }
          .disabled(link.testing || link.addressText.isEmpty)
        } header: {
          Text("Address")
        } footer: {
          Text(
            "`vividhome serve --lan` prints this on the PC; the port is 8765 unless it was changed. "
              + "Away from home, the PC's tailnet name (`https://<pc>.<tailnet>.ts.net`, from "
              + "`tailscale serve`) works from anywhere Tailscale is connected.")
        }

        Section {
          TextField("3f9a-1c2b-7e4d-0a61", text: $link.pairingCode)
            .font(.body.monospaced())
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Pairing code")
        } footer: {
          Text(
            "Printed by `vividhome serve --lan` on the PC. Needed only to send captures there; "
              + "reading the rendering needs nothing. Test checks it along with the address.")
        }

        Section("Result") {
          if let problem = link.problem {
            Label(problem, systemImage: "xmark.octagon.fill")
              .foregroundStyle(.red).font(.footnote)
          } else if let index = link.index {
            Label(
              "\(index.store): \(index.projects.count) project\(index.projects.count == 1 ? "" : "s"), "
                + "\(index.sessionCount) session\(index.sessionCount == 1 ? "" : "s"), "
                + "\(index.renderedLevelCount) rendered level\(index.renderedLevelCount == 1 ? "" : "s")",
              systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green).font(.footnote)
            if let checkedAt = link.checkedAt {
              Text("Checked \(checkedAt.formatted(date: .omitted, time: .shortened)); "
                + "pipeline \(index.vividhome).")
                .font(.footnote).foregroundStyle(.secondary)
            }
            if let pairingProblem = link.pairingProblem {
              Label(pairingProblem, systemImage: "key.slash")
                .foregroundStyle(.orange).font(.footnote)
            } else if link.hasPairingCode {
              Label("Pairing code accepted; captures can be sent.", systemImage: "key.fill")
                .foregroundStyle(.green).font(.footnote)
            }
          } else {
            Text("Not tested yet.").font(.footnote).foregroundStyle(.secondary)
          }
        }

        Section {
          Text("Everything the PC serves is readable by anyone who can reach it: this network "
            + "while `serve --lan` runs, or your own devices on the tailnet. Nothing can change "
            + "the store except captures sent with the pairing code, and those land in an inbox "
            + "the PC checks before it keeps them. The app never deletes anything on the PC.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("PC")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
      }
      .onAppear { link.startBrowsing() }
      .onDisappear { link.stopBrowsing() }
    }
  }
}
