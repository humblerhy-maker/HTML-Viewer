import SwiftUI
import UIKit

struct MemorySheet: View {
    let app: VaultAppRecord
    var popToLibrary: (() -> Void)? = nil
    @EnvironmentObject var store: VaultFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirm1 = false
    @State private var confirm2 = false
    @State private var typed = ""
    @State private var replacing = false
    @State private var wipeOnReplace = false

    var live: VaultAppRecord {
        store.apps.first(where: { $0.id == app.id }) ?? app
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Session", value: live.hasMemory ? "Has been run" : "No stored session yet")
                    LabeledContent("Last cleared", value: dateText(live.lastClearedAt))
                    LabeledContent("Last backup", value: dateText(live.lastBackupAt))
                    LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: Int64(live.byteSize), countStyle: .file))
                }
                Section {
                    Text("Memory is this file’s WebKit website data (localStorage, IndexedDB, cookies). iOS does not allow a full WK data export. If the HTML app has its own backup button, use that. You can always keep a copy of the HTML file.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Backup HTML file") {
                        shareOriginal()
                    }
                }
                Section("Restore / replace") {
                    Text("Replace HTML file but keep memory, or replace and wipe, or re-import as a new app from Library.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Wipe memory on replace", isOn: $wipeOnReplace)
                    Button("Replace HTML file") { replacing = true }
                }
                Section {
                    Button("Delete memory", role: .destructive) {
                        if store.settings.confirmMemoryWipe {
                            confirm1 = true
                        } else {
                            store.wipeMemory(live.id) {}
                        }
                    }
                }
            }
            .navigationTitle("Memory")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { goBack() } } }
            .fileImporter(isPresented: $replacing, allowedContentTypes: [.html, .zip], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    try? store.importOne(url, replacing: live.id, wipeMemory: wipeOnReplace)
                }
            }
            .alert("Delete memory for this file?", isPresented: $confirm1) {
                Button("Continue", role: .destructive) { confirm2 = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only this file’s website data is targeted. Other vault items are untouched. You will be asked again.")
            }
            .alert("Type DELETE", isPresented: $confirm2) {
                TextField("DELETE", text: $typed)
                Button("Delete memory", role: .destructive) {
                    if typed == "DELETE" {
                        store.wipeMemory(live.id) {}
                    }
                    typed = ""
                }
                Button("Cancel", role: .cancel) { typed = "" }
            }
        }
    }

    private func goBack() {
        dismiss()
        if let popToLibrary {
            DispatchQueue.main.async { popToLibrary() }
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func shareOriginal() {
        guard let data = store.originalData(for: live) else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(live.originalFilename)
        try? data.write(to: tmp)
        store.markBackup(live.id)
        let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.windows.first { $0.isKeyWindow }?.rootViewController?.present(av, animated: true)
    }
}
