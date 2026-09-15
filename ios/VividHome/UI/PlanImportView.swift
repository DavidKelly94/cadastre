import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VividHomeCore

/// Bring a floor plan into the project, per level.
///
/// Three ways in, because a plan arrives however the builder has it: a PDF from
/// the architect, a photo already in the library, or the camera pointed at a
/// drawing taped to a stud wall. The last is the case the app has to be good at
/// and the one a clean PDF render would let us design past.
struct PlanImportView: View {
  @ObservedObject var store: PlanStore
  let levelName: String
  let onDone: () -> Void

  @State private var picked: PhotosPickerItem?
  @State private var showingFiles = false
  @State private var preview: UIImage?
  @State private var source: PlanSource?
  @State private var originalData: Data?
  @State private var pdfPageCount = 0
  @State private var pdfPage = 0
  @State private var pdfDocumentData: Data?
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      Form {
        if let preview {
          Section {
            Image(uiImage: preview)
              .resizable().scaledToFit()
              .frame(maxWidth: .infinity)
              .background(Color(.secondarySystemBackground))
              .clipShape(RoundedRectangle(cornerRadius: 12))
          } header: {
            Text("\(Int(preview.size.width)) × \(Int(preview.size.height)) px")
          } footer: {
            Text(
              "The phone does not straighten a photographed plan. Shoot it as square-on as you "
                + "can; `vividhome plan correct` fixes the rest on the PC.")
          }

          if pdfPageCount > 1 {
            Section("Page") {
              Stepper("Page \(pdfPage + 1) of \(pdfPageCount)", value: $pdfPage, in: 0...(pdfPageCount - 1))
                .onChange(of: pdfPage) { _, page in renderPDF(page: page) }
            }
          }
        }

        Section {
          PhotosPicker(selection: $picked, matching: .images) {
            Label("Choose a photo", systemImage: "photo.on.rectangle")
          }
          Button {
            showingFiles = true
          } label: {
            Label("Choose a PDF", systemImage: "doc.richtext")
          }
        } footer: {
          Text("A plan is optional for recording, but a capture cannot be placed on the record "
            + "without one.")
        }

        if preview != nil {
          Section {
            Button("Use this plan") { save() }
          }
        }
      }
      .navigationTitle("Add a plan")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
      }
      .onChange(of: picked) { _, item in loadPhoto(item) }
      .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.pdf]) { result in
        if case .success(let url) = result { loadPDF(url) }
      }
      .alert("Could not add the plan", isPresented: .constant(failure != nil)) {
        Button("OK") { failure = nil }
      } message: {
        Text(failure ?? "")
      }
    }
  }

  // MARK: - Loading

  private func loadPhoto(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task {
      guard let data = try? await item.loadTransferable(type: Data.self),
        let image = UIImage(data: data)
      else {
        failure = "That image could not be read."
        return
      }
      preview = image
      pdfPageCount = 0
      pdfDocumentData = nil
      // HEIC is what the camera writes; a library photo may be either.
      let heic = data.count > 12 && data.prefix(12).dropFirst(4).elementsEqual(Array("ftypheic".utf8))
      source = PlanSource(file: heic ? "source.heic" : "source.jpg", kind: heic ? .heic : .jpeg)
      originalData = data
    }
  }

  private func loadPDF(_ url: URL) {
    // A file from the document picker is outside the sandbox until asked for.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) else {
      failure = "That PDF could not be opened."
      return
    }
    pdfDocumentData = data
    pdfPageCount = document.pageCount
    pdfPage = 0
    originalData = data
    renderPDF(page: 0)
  }

  private func renderPDF(page index: Int) {
    guard let data = pdfDocumentData, let document = PDFDocument(data: data),
      let page = document.page(at: index)
    else { return }
    let bounds = page.bounds(for: .mediaBox)
    // 200 dpi: a plan's thinnest printed line is about 0.25 pt, and below this it
    // drops out of the raster entirely.
    let scale = min(PlanStore.maxEdge / max(bounds.width, bounds.height), 200.0 / 72.0)
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    preview = UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      context.cgContext.translateBy(x: 0, y: size.height)
      context.cgContext.scaleBy(x: scale, y: -scale)
      page.draw(with: .mediaBox, to: context.cgContext)
    }
    source = PlanSource(file: "source.pdf", kind: .pdf, page: index + 1)
  }

  private func save() {
    guard let preview else { return }
    do {
      try store.importPlan(
        image: preview, levelName: levelName, source: source, originalData: originalData)
      onDone()
    } catch {
      failure = error.localizedDescription
    }
  }
}
