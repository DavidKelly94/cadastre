import SwiftUI
import WebKit

/// The PC's rendered page for a level, shown as the browser would show it.
///
/// A web view rather than a native renderer, per ADR-0028: the viewer is
/// written once and the phone shows what the browser shows. The page itself
/// works by touch (`inspector.py`), so nothing here has to translate.
struct RenderingView: View {
  let url: URL
  let title: String
  let generatedAt: Date?
  let onDone: () -> Void

  var body: some View {
    NavigationStack {
      WebPage(url: url)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
        }
        // A footer rather than a bottom-bar item: the bar squeezed the text
        // into a pill that read "Fro..." on the first walk.
        .safeAreaInset(edge: .bottom) {
          Text(age)
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
  }

  /// How old the picture is. A page opened once stays openable from the web
  /// view's cache with the PC off, so the owner has to be told when it was made.
  private var age: String {
    guard let generatedAt else { return "Age unknown" }
    return "From the PC, \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
  }
}

struct WebPage: UIViewRepresentable {
  let url: URL

  func makeUIView(context: Context) -> WKWebView {
    let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    view.allowsBackForwardNavigationGestures = false
    view.load(URLRequest(url: url))
    return view
  }

  func updateUIView(_ view: WKWebView, context: Context) {
    if view.url != url {
      view.load(URLRequest(url: url))
    }
  }
}
