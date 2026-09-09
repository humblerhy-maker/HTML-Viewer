import SwiftUI
import WebKit

/// Throwaway WebView for Edit → Test HTML. Ephemeral data store.
/// Never shares the Run tab's WKWebsiteDataStore.
struct DraftWebView: UIViewRepresentable {
    let html: String
    var reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.reloadToken = reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator {
        var reloadToken: Int = 0
    }
}
