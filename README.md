# HTML Viewer

Native iPhone app (SwiftUI + WKWebView) that runs uploaded HTML files as their own apps.

**HTML Viewer never modifies, minifies, pretty-prints, injects into, reformats, or “optimizes” your HTML.**

Home screen name: **HTML Viewer**. Xcode project folder is still `HTMLVault` (open `HTMLVault.xcodeproj`).

## Install on your iPhone

Apple does not let a GitHub ZIP install as an App Store app by itself. You compile once with Xcode, then the app lives on the phone.

You need a Mac with Xcode 15+ and a free Apple ID.

1. On a Mac, download this repo (Code → Download ZIP) or clone it.
2. Unzip if needed, then open `HTMLVault.xcodeproj`.
3. Select the **HTMLVault** target → Signing & Capabilities → Team → your Apple ID.
4. Plug in the iPhone, trust the computer, pick the phone as the run destination.
5. Press Run. On the phone: Settings → General → VPN & Device Management → trust your developer certificate, then open **HTML Viewer**.

iOS 16+ (per-file website-data isolation uses `WKWebsiteDataStore(forIdentifier:)` on iOS 17+).

The first launch asks for Photos only if a page you open uses a file/image picker.

## How Add File works

- **Add** picks `.html` / `.htm` / `.zip` (multiple allowed) or a folder.
- Each import is copied as **raw bytes** into `Application Support/HTMLVault/apps/{appId}/`.
- `{appId}` is a UUID created once. The entry path is stored and reused.
- ZIP/folder contents are unpacked as-is (not flattened, not renamed) except they live in that app’s directory.
- Entry file = first `index.html` / `index.htm`, else the only HTML file.
- SHA-256 of the uploaded bytes is stored and shown in Info so you can see nothing changed.
- Replace overwrites bytes for the same `appId` and **keeps memory** unless you toggle wipe.

## How Memory wipe works

Memory = that appId’s WebKit website data (localStorage, IndexedDB, cookies).

- Each app uses a persistent `WKWebsiteDataStore` keyed by `appId` (iOS 17+). Non-persistent stores are not used for Run.
- Refresh calls `webView.reload()` of the same `file://` URL. It does not recreate the folder, re-import, or clear data.
- **Delete memory** asks twice (when the setting is on), then removes website data for that `appId` only and reloads.
- iOS does not let apps snapshot/restore WK website data. HTML Viewer does not fake that. Use:
  - Replace HTML file but keep memory
  - Replace HTML file and wipe memory
  - Re-import as a new app (fresh memory)
- **Reset entire vault** is labeled as such and requires typing `RESET ENTIRE VAULT`.

If a page has its own backup button, use that for localStorage exports.

## Run mode

Fullscreen WKWebView, edge-to-edge, no Safari chrome. Overlay (handle at top): Back · Refresh · Zoom · Source · Edit · Memory · Info. The overlay stays until you tap Close or the handle. Zoom is A− / 100% / A+ only (80–150%, steps of 10%). Pinch-zoom of the page is off. Focusing an input restores the saved pageZoom (no injected CSS). Edit is a separate workbench: find/replace/remove, push to a draft, test in an ephemeral WebView. Save Draft Over This File is the only write back to disk.
