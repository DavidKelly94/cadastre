import SwiftUI
import VividHomeCore

/// The photos a capture holds, on the phone, and a way to keep any of them.
///
/// The first of ADR-0028's two asks. Reads `frames.jsonl` and `stills.jsonl`
/// through the core package, so it works on any session on the phone, ingested
/// or not, and never touches ARKit. Every image is shown turned the way the
/// phone was held, and labelled from the session itself.
struct SessionPhotosView: View {
  let layout: SessionLayout
  let manifest: Manifest?

  @State private var photos = SessionPhotos(photos: [])
  @State private var stride = 5
  @State private var selecting = false
  @State private var selected: Set<String> = []
  @State private var viewing: SessionPhotos.Photo?
  @State private var saving = false
  @State private var notice: String?

  private var sessionID: String { layout.root.lastPathComponent }
  private var shown: [SessionPhotos.Photo] { photos.sampled(stride: stride) }
  private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

  var body: some View {
    Group {
      if photos.photos.isEmpty {
        ContentUnavailableView(
          "No photos", systemImage: "photo",
          description: Text("This capture wrote no keyframes."))
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 2) {
            ForEach(shown) { photo in
              PhotoCell(
                url: layout.root.appendingPathComponent(photo.path), photo: photo,
                selected: selected.contains(photo.id), selecting: selecting
              )
              .onTapGesture { tap(photo) }
            }
          }
          Text(footer).font(.footnote).foregroundStyle(.secondary).padding()
        }
      }
    }
    .navigationTitle(manifest?.room.name ?? "Photos")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Show", selection: $stride) {
            Text("Every keyframe").tag(1)
            Text("Every 5th keyframe").tag(5)
            Text("Every 10th keyframe").tag(10)
          }
        } label: {
          Image(systemName: "line.3.horizontal.decrease.circle")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button(selecting ? "Cancel" : "Select") {
          selecting.toggle()
          selected = []
        }
      }
      ToolbarItem(placement: .bottomBar) {
        if selecting {
          Button {
            save(shown.filter { selected.contains($0.id) })
          } label: {
            Label("Save \(selected.count) to Photos", systemImage: "square.and.arrow.down")
          }
          .disabled(selected.isEmpty || saving)
        }
      }
    }
    .task {
      // Hundreds of lines of JSONL: off the main thread, where a hitch would
      // be the first thing the owner noticed about this screen.
      let layout = layout
      photos = await Task.detached(priority: .userInitiated) {
        SessionPhotos.read(at: layout)
      }.value
    }
    .fullScreenCover(item: $viewing) { photo in
      PhotoDetailView(
        layout: layout, manifest: manifest, photos: shown, start: photo,
        onSave: { save([$0]) })
    }
    .alert(
      "Photos", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    ) {
      Button("OK") { notice = nil }
    } message: {
      Text(notice ?? "")
    }
  }

  private var footer: String {
    let stills = photos.stillCount
    let keyframes = photos.keyframeCount
    let showing = stride == 1 ? "every keyframe" : "every \(stride)th keyframe"
    return "\(keyframes) keyframes and \(stills) still\(stills == 1 ? "" : "s"); showing \(showing) "
      + "and every still. Saving copies a photo to your camera roll with its label; "
      + "the capture itself is never changed."
  }

  private func tap(_ photo: SessionPhotos.Photo) {
    if selecting {
      if selected.contains(photo.id) {
        selected.remove(photo.id)
      } else {
        selected.insert(photo.id)
      }
    } else {
      viewing = photo
    }
  }

  private func save(_ items: [SessionPhotos.Photo]) {
    guard !items.isEmpty, !saving else { return }
    saving = true
    let jobs = items.map { photo in
      PhotoExporter.Job(
        url: layout.root.appendingPathComponent(photo.path),
        label: PhotoLabel.make(for: photo, manifest: manifest, sessionID: sessionID),
        orientation: DisplayOrientation.from(pose: photo.pose))
    }
    Task {
      do {
        let count = try await PhotoExporter.save(jobs)
        notice = count == 1 ? "Saved to Photos." : "Saved \(count) photos to Photos."
        selecting = false
        selected = []
      } catch {
        notice = error.localizedDescription
      }
      saving = false
    }
  }
}

/// One cell of the grid: a thumbnail, and marks for a still and for a tap.
private struct PhotoCell: View {
  let url: URL
  let photo: SessionPhotos.Photo
  let selected: Bool
  let selecting: Bool

  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.secondary.opacity(0.15))
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          if let image {
            Image(uiImage: image).resizable().scaledToFill()
          }
        }
        .clipped()
      VStack {
        HStack {
          if !photo.landmarkLabels.isEmpty {
            badge("mappin.circle.fill")
          }
          Spacer()
          if photo.kind == .still {
            badge("camera.fill")
          }
        }
        Spacer()
        HStack {
          Spacer()
          if selecting {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
              .font(.title3)
              .foregroundStyle(selected ? Color.accentColor : Color.white)
              .shadow(radius: 2)
          }
        }
      }
      .padding(6)
    }
    .contentShape(Rectangle())
    .task(id: url) {
      let orientation = DisplayOrientation.from(pose: photo.pose)
      image = await Task.detached(priority: .utility) {
        PhotoLoader.thumbnail(at: url, maxPixel: 360, orientation: orientation)
      }.value
    }
  }

  private func badge(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.caption2)
      .padding(4)
      .background(.thinMaterial, in: Circle())
  }
}

/// One photo full-screen, with its label, and the rest of the capture a swipe away.
struct PhotoDetailView: View {
  let layout: SessionLayout
  let manifest: Manifest?
  let photos: [SessionPhotos.Photo]
  let start: SessionPhotos.Photo
  let onSave: (SessionPhotos.Photo) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var current: String = ""

  var body: some View {
    NavigationStack {
      TabView(selection: $current) {
        ForEach(photos) { photo in
          PhotoPage(
            url: layout.root.appendingPathComponent(photo.path), photo: photo,
            label: PhotoLabel.make(
              for: photo, manifest: manifest, sessionID: layout.root.lastPathComponent)
          )
          .tag(photo.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .background(Color.black)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            if let photo = photos.first(where: { $0.id == current }) {
              onSave(photo)
            }
          } label: {
            Label("Save to Photos", systemImage: "square.and.arrow.down")
          }
        }
      }
      .onAppear { current = start.id }
    }
  }
}

private struct PhotoPage: View {
  let url: URL
  let photo: SessionPhotos.Photo
  let label: PhotoLabel

  @State private var image: UIImage?

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if let image {
          Image(uiImage: image).resizable().scaledToFit()
        } else {
          ProgressView().tint(.white)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      VStack(alignment: .leading, spacing: 2) {
        Text(label.headline).font(.footnote.weight(.semibold))
        Text(label.frame + dateText).font(.footnote)
        if let landmarks = label.landmarks {
          Text(landmarks).font(.footnote).foregroundStyle(Tokens.warn)
        }
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .background(Color.black)
    .task(id: url) {
      let orientation = DisplayOrientation.from(pose: photo.pose)
      image = await Task.detached(priority: .userInitiated) {
        PhotoLoader.full(at: url, orientation: orientation)
      }.value
    }
  }

  private var dateText: String {
    guard let takenAt = label.takenAt else { return "" }
    return " · " + takenAt.formatted(date: .abbreviated, time: .shortened)
  }
}
