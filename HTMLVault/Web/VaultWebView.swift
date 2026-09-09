import SwiftUI
import WebKit
import UIKit

struct VaultWebView: UIViewRepresentable {
    let app: VaultAppRecord
    let folder: URL
    let entry: URL
    var zoom: Double
    var reloadToken: Int
    var onTerminated: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTerminated: onTerminated, savedZoom: CGFloat(zoom))
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WebsiteDataBox.store(for: app.id)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        lockZoom(webView)
        webView.pageZoom = CGFloat(zoom)
        webView.loadFileURL(entry, allowingReadAccessTo: folder)
        context.coordinator.reloadToken = reloadToken
        context.coordinator.savedZoom = CGFloat(zoom)
        context.coordinator.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.savedZoom = CGFloat(zoom)
        lockZoom(webView)
        if abs(Double(webView.pageZoom) - zoom) > 0.001 {
            webView.pageZoom = CGFloat(zoom)
        }
        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.reload()
        }
        context.coordinator.onTerminated = onTerminated
        context.coordinator.restoreZoom()
    }

    private func lockZoom(_ webView: WKWebView) {
        webView.scrollView.bounces = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var reloadToken: Int = 0
        var onTerminated: () -> Void
        var savedZoom: CGFloat
        weak var webView: WKWebView?
        private var observers: [NSObjectProtocol] = []
        private var child: WKWebView?

        init(onTerminated: @escaping () -> Void, savedZoom: CGFloat) {
            self.onTerminated = onTerminated
            self.savedZoom = savedZoom
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            let names: [Notification.Name] = [
                UIResponder.keyboardWillShowNotification,
                UIResponder.keyboardDidShowNotification,
                UIResponder.keyboardWillChangeFrameNotification,
                UIResponder.keyboardDidChangeFrameNotification,
                UIResponder.keyboardWillHideNotification,
                UIResponder.keyboardDidHideNotification,
            ]
            for name in names {
                let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.restoreZoom()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.restoreZoom() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { self?.restoreZoom() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.restoreZoom() }
                }
                observers.append(token)
            }
        }

        func restoreZoom() {
            guard let webView else { return }
            webView.pageZoom = savedZoom
            webView.scrollView.zoomScale = 1
            webView.scrollView.minimumZoomScale = 1
            webView.scrollView.maximumZoomScale = 1
            webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            restoreZoom()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onTerminated()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        func webViewDidClose(_ webView: WKWebView) {
            child = nil
        }
    }
}
