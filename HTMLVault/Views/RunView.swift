import SwiftUI

struct RunView: View {
    let appId: UUID
    @EnvironmentObject var store: VaultFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var overlay = false
    @State private var zoomOpen = false
    @State private var sourceOpen = false
    @State private var editOpen = false
    @State private var memoryOpen = false
    @State private var infoOpen = false
    @State private var terminated = false
    @State private var reloadToken = 0

    var app: VaultAppRecord? {
        store.apps.first(where: { $0.id == appId })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let app {
                VaultWebView(
                    app: app,
                    folder: store.folder(for: app.id),
                    entry: store.entryURL(for: app),
                    zoom: app.pageZoom,
                    reloadToken: reloadToken,
                    onTerminated: { terminated = true }
                )
                .id(app.id)
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button("Back") { dismiss() }
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                Button {
                    showOverlay()
                } label: {
                    Capsule()
                        .fill(.white.opacity(0.45))
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .frame(width: 112, height: 28)
                }
                if overlay {
                    toolbar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }

            if terminated {
                VStack(spacing: 12) {
                    Text("This page stopped. Reload the same file — it was not deleted.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("Reload") {
                        terminated = false
                        reloadToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.black.opacity(0.72))
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $zoomOpen) {
            if let app { ZoomSheet(app: app) }
        }
        .sheet(isPresented: $memoryOpen) {
            if let app { MemorySheet(app: app, popToLibrary: { dismiss() }) }
        }
        .sheet(isPresented: $infoOpen) {
            if let app { InfoSheet(app: app, popToLibrary: { dismiss() }) }
        }
        .fullScreenCover(isPresented: $sourceOpen) {
            if let app { SourceView(app: app) }
        }
        .fullScreenCover(isPresented: $editOpen) {
            if let app { EditView(app: app) }
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                pill("Back", system: "chevron.left") { dismiss() }
                pill("Refresh", system: "arrow.clockwise") { reloadToken += 1 }
                pill("Zoom", system: "textformat.size") { zoomOpen = true }
                pill("Source", system: "doc.text") { sourceOpen = true }
                pill("Edit", system: "pencil") { editOpen = true }
                pill("Memory", system: "internaldrive") { memoryOpen = true }
                pill("Info", system: "info.circle") { infoOpen = true }
                Button("Close") { overlay = false }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
    }

    private func pill(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .foregroundStyle(.primary)
    }

    private func showOverlay() {
        overlay.toggle()
    }
}

struct ZoomSheet: View {
    let app: VaultAppRecord
    @EnvironmentObject var store: VaultFileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Manual only. Pinch-zoom is off on the running page. Changing zoom does not reload or wipe memory.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                HStack {
                    Button("A−") { store.setZoom(app.id, app.pageZoom - ZoomRange.step) }
                    Spacer()
                    Text("\(Int((store.apps.first(where: { $0.id == app.id })?.pageZoom ?? app.pageZoom) * 100))%")
                        .font(.title2.monospacedDigit())
                    Spacer()
                    Button("A+") { store.setZoom(app.id, app.pageZoom + ZoomRange.step) }
                }
                .padding()
                Button("100%") { store.setZoom(app.id, 1) }
                Spacer()
            }
            .padding()
            .navigationTitle("Zoom")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
