import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: VaultFileStore
    @State private var query = ""
    @State private var picking = false
    @State private var pickingFolder = false
    @State private var settingsOpen = false
    @State private var running: VaultAppRecord?
    @State private var source: VaultAppRecord?
    @State private var editing: VaultAppRecord?
    @State private var memoryApp: VaultAppRecord?
    @State private var infoApp: VaultAppRecord?
    @State private var renameApp: VaultAppRecord?
    @State private var renameText = ""
    @State private var deleteApp: VaultAppRecord?
    @State private var wipeOnDelete = false
    @State private var errorMessage: String?

    var filtered: [VaultAppRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return store.apps }
        return store.apps.filter {
            $0.displayName.lowercased().contains(q)
                || $0.originalFilename.lowercased().contains(q)
                || $0.fileSHA256.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty {
                    empty
                } else {
                    List {
                        ForEach(filtered) { app in
                            Button {
                                store.markOpened(app.id)
                                running = app
                            } label: {
                                AppRowView(app: app)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteApp = app
                                } label: { Text("Delete") }
                                Button { memoryApp = app } label: { Text("Memory") }
                                Button { source = app } label: { Text("Source") }
                                Button { editing = app } label: { Text("Edit") }
                                Button { store.markOpened(app.id); running = app } label: { Text("Run") }
                            }
                            .contextMenu {
                                Button("Run") { store.markOpened(app.id); running = app }
                                Button("Edit") { editing = app }
                                Button("Source") { source = app }
                                Button("Memory") { memoryApp = app }
                                Button("Info") { infoApp = app }
                                Button("Rename") { renameApp = app; renameText = app.displayName }
                                Button("Delete", role: .destructive) { deleteApp = app }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { settingsOpen = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("HTML or ZIP") { picking = true }
                        Button("Folder") { pickingFolder = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [UTType.html, UTType.zip, UTType.data], allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .sheet(item: $memoryApp) { app in
                MemorySheet(app: app)
            }
            .sheet(item: $infoApp) { app in
                InfoSheet(app: app)
            }
            .sheet(isPresented: $settingsOpen) {
                SettingsView()
            }
            .fullScreenCover(item: $running) { app in
                RunView(appId: app.id)
            }
            .fullScreenCover(item: $source) { app in
                SourceView(app: app)
            }
            .fullScreenCover(item: $editing) { app in
                EditView(app: app)
            }
            .alert("Rename", isPresented: Binding(get: { renameApp != nil }, set: { if !$0 { renameApp = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let id = renameApp?.id { store.rename(id, to: renameText) }
                    renameApp = nil
                }
                Button("Cancel", role: .cancel) { renameApp = nil }
            }
            .alert("Delete this file?", isPresented: Binding(get: { deleteApp != nil }, set: { if !$0 { deleteApp = nil } })) {
                Button("Delete file", role: .destructive) {
                    if let app = deleteApp { store.deleteApp(app.id, wipeData: wipeOnDelete) }
                    deleteApp = nil
                }
                Button("Delete file and wipe memory", role: .destructive) {
                    if let app = deleteApp { store.deleteApp(app.id, wipeData: true) }
                    deleteApp = nil
                }
                Button("Cancel", role: .cancel) { deleteApp = nil }
            } message: {
                Text("The stored bytes and this library item will be removed. Other files stay.")
            }
            .alert("Import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.square")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Add an HTML file. It will run as its own app. Your file will not be changed.")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Add") { picking = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            do {
                _ = try store.importFiles(urls)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct AppRowView: View {
    let app: VaultAppRecord

    var body: some View {
        HStack(spacing: 12) {
            Text(app.kind.uppercased())
                .font(.caption2.monospaced())
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.displayName).font(.headline).foregroundStyle(.primary)
                    if app.hasMemory {
                        Text("Memory")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tertiary, in: Capsule())
                    }
                }
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(app.byteSize), countStyle: .file)) · \(opened)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var opened: String {
        guard let date = app.lastOpenedAt else { return "Never opened" }
        return date.formatted(.relative(presentation: .named))
    }
}
