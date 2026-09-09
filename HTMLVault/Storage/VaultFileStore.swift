import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VaultFileStore: ObservableObject {
    static let shared = VaultFileStore()

    @Published var apps: [VaultAppRecord] = []
    @Published var settings: VaultSettings = .default

    let root: URL
    let appsRoot: URL
    private let indexURL: URL
    private let settingsURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("HTMLVault", isDirectory: true)
        appsRoot = root.appendingPathComponent("apps", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        settingsURL = root.appendingPathComponent("settings.json")
        try? FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        load()
    }

    func folder(for id: UUID) -> URL {
        appsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func entryURL(for app: VaultAppRecord) -> URL {
        folder(for: app.id).appendingPathComponent(app.entryRelativePath)
    }

    func load() {
        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder().decode(VaultIndex.self, from: data) {
            apps = sorted(index.apps)
        }
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(VaultSettings.self, from: data) {
            settings = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(VaultIndex(apps: apps)) {
            try? data.write(to: indexURL, options: .atomic)
        }
        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    func sorted(_ items: [VaultAppRecord]) -> [VaultAppRecord] {
        items.sorted { a, b in
            let ao = a.lastOpenedAt ?? .distantPast
            let bo = b.lastOpenedAt ?? .distantPast
            if ao != bo { return ao > bo }
            return a.createdAt > b.createdAt
        }
    }

    func importFiles(_ urls: [URL]) throws -> Int {
        var count = 0
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            try importOne(url)
            count += 1
        }
        save()
        return count
    }

    func importOne(_ url: URL, replacing id: UUID? = nil, wipeMemory: Bool = false) throws {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let destId = id ?? UUID()
        let dest = folder(for: destId)
        if id == nil {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        }
        let originalBytes = try Data(contentsOf: url)
        let hash = sha256Hex(originalBytes)
        var kind = "html"
        if ext == "zip" {
            kind = "zip"
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try ZipExtractor.extract(data: originalBytes, to: dest)
        } else if ext == "html" || ext == "htm" {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let target = dest.appendingPathComponent(name)
            try originalBytes.write(to: target, options: .atomic)
        } else if isDirectory(url) {
            kind = "folder"
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
        } else {
            throw VaultError.unsupportedType(name)
        }
        try originalBytes.write(to: dest.appendingPathComponent(".original.bin"), options: .atomic)
        let entry = try findEntry(in: dest)
        let fileCount = try countFiles(in: dest)
        let existing = apps.first(where: { $0.id == destId })
        let record = VaultAppRecord(
            id: destId,
            displayName: existing?.displayName ?? (url.deletingPathExtension().lastPathComponent),
            originalFilename: name,
            entryRelativePath: entry,
            createdAt: existing?.createdAt ?? Date(),
            lastOpenedAt: existing?.lastOpenedAt,
            pageZoom: existing?.pageZoom ?? settings.defaultZoom,
            fileSHA256: hash,
            byteSize: originalBytes.count,
            fileCount: fileCount,
            kind: kind,
            lastClearedAt: wipeMemory ? Date() : existing?.lastClearedAt,
            lastBackupAt: existing?.lastBackupAt,
            hasMemory: wipeMemory ? false : (existing?.hasMemory ?? false)
        )
        if let idx = apps.firstIndex(where: { $0.id == destId }) {
            apps[idx] = record
        } else {
            apps.insert(record, at: 0)
        }
        apps = sorted(apps)
        save()
        if id != nil {
            EditorStore.shared.drop(destId)
        }
        if wipeMemory {
            WebsiteDataBox.wipe(appId: destId) {}
        }
    }

    func markOpened(_ id: UUID) {
        guard let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[idx].lastOpenedAt = Date()
        apps[idx].hasMemory = true
        apps = sorted(apps)
        save()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[idx].displayName = trimmed
        save()
    }

    func setZoom(_ id: UUID, _ zoom: Double) {
        guard let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[idx].pageZoom = ZoomRange.clamp(zoom)
        save()
    }

    func deleteApp(_ id: UUID, wipeData: Bool) {
        let dir = folder(for: id)
        try? FileManager.default.removeItem(at: dir)
        apps.removeAll { $0.id == id }
        save()
        EditorStore.shared.drop(id)
        if wipeData {
            WebsiteDataBox.wipe(appId: id) {}
        }
    }

    func wipeMemory(_ id: UUID, completion: @escaping () -> Void) {
        WebsiteDataBox.wipe(appId: id) {
            Task { @MainActor in
                if let idx = self.apps.firstIndex(where: { $0.id == id }) {
                    self.apps[idx].hasMemory = false
                    self.apps[idx].lastClearedAt = Date()
                    self.save()
                }
                completion()
            }
        }
    }

    func markBackup(_ id: UUID) {
        guard let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[idx].lastBackupAt = Date()
        save()
    }

    func resetEntireVault() {
        try? FileManager.default.removeItem(at: appsRoot)
        try? FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        apps = []
        save()
        EditorStore.shared.dropAll()
    }

    func saveDraftOverFile(_ id: UUID, draft: String, wipeMemory: Bool) {
        guard let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        let url = entryURL(for: apps[idx])
        let data = Data(draft.utf8)
        try? data.write(to: url, options: .atomic)
        apps[idx].fileSHA256 = sha256Hex(data)
        apps[idx].byteSize = data.count
        if wipeMemory {
            apps[idx].hasMemory = false
            apps[idx].lastClearedAt = Date()
            WebsiteDataBox.wipe(appId: id) {}
        }
        save()
    }

    func readEntryText(_ app: VaultAppRecord) -> String {
        let url = entryURL(for: app)
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
    }

    func originalData(for app: VaultAppRecord) -> Data? {
        let original = folder(for: app.id).appendingPathComponent(".original.bin")
        if let data = try? Data(contentsOf: original) { return data }
        return try? Data(contentsOf: entryURL(for: app))
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func findEntry(in folder: URL) throws -> String {
        let files = try collectRelativePaths(in: folder)
        let htmls = files.filter { $0.lowercased().hasSuffix(".html") || $0.lowercased().hasSuffix(".htm") }
        guard !htmls.isEmpty else { throw VaultError.noHTML }
        let indexes = htmls.filter {
            let base = ($0 as NSString).lastPathComponent.lowercased()
            return base == "index.html" || base == "index.htm"
        }
        let pool = indexes.isEmpty ? htmls : indexes
        return pool.sorted { a, b in
            let da = a.split(separator: "/").count
            let db = b.split(separator: "/").count
            if da != db { return da < db }
            return a < b
        }[0]
    }

    private func collectRelativePaths(in folder: URL) throws -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var paths: [String] = []
        for case let file as URL in enumerator {
            let rel = file.path.replacingOccurrences(of: folder.path + "/", with: "")
            if rel.hasPrefix(".") { continue }
            paths.append(rel)
        }
        return paths
    }

    private func countFiles(in folder: URL) throws -> Int {
        try collectRelativePaths(in: folder).count
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

enum VaultError: LocalizedError {
    case unsupportedType(String)
    case noHTML
    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name): return "Skipped \(name): add .html, .htm, or .zip"
        case .noHTML: return "No HTML file found"
        }
    }
}
