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
              + "`vividhome serve --lan`.")
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
          TextField("192.168.1.20 or 192.168.1.20:8765", text: $link.addressText)
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
          Text("`vividhome serve --lan` prints this on the PC. The port is 8765 unless it was changed.")
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
          } else {
            Text("Not tested yet.").font(.footnote).foregroundStyle(.secondary)
          }
        }

        Section {
          Text("Everything the PC serves is readable by anyone on this network while "
            + "`serve --lan` is running, and nothing on the network can change it. "
            + "The app only ever reads.")
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
