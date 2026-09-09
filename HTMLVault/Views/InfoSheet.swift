import SwiftUI

struct InfoSheet: View {
    let app: VaultAppRecord
    var popToLibrary: (() -> Void)? = nil
    @EnvironmentObject var store: VaultFileStore
    @Environment(\.dismiss) private var dismiss

    var live: VaultAppRecord {
        store.apps.first(where: { $0.id == app.id }) ?? app
    }

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Name", value: live.displayName)
                LabeledContent("On-disk name", value: live.originalFilename)
                LabeledContent("Entry", value: live.entryRelativePath)
                LabeledContent("App id", value: live.id.uuidString)
                LabeledContent("Kind", value: live.kind)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(live.byteSize), countStyle: .file))
                LabeledContent("Files", value: "\(live.fileCount)")
                LabeledContent("Zoom", value: "\(Int(live.pageZoom * 100))%")
                Section("SHA-256") {
                    Text(live.fileSHA256)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Recorded on import from the exact stored bytes. HTML Viewer does not rewrite the file.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Info")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") {
                dismiss()
                if let popToLibrary {
                    DispatchQueue.main.async { popToLibrary() }
                }
            } } }
        }
        .presentationDetents([.large])
    }
}
