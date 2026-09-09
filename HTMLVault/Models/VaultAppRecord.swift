import Foundation

struct VaultAppRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var displayName: String
    var originalFilename: String
    var entryRelativePath: String
    var createdAt: Date
    var lastOpenedAt: Date?
    var pageZoom: Double
    var fileSHA256: String
    var byteSize: Int
    var fileCount: Int
    var kind: String
    var lastClearedAt: Date?
    var lastBackupAt: Date?
    var hasMemory: Bool
}

struct VaultIndex: Codable {
    var apps: [VaultAppRecord]
}

struct VaultSettings: Codable {
    var defaultZoom: Double
    var confirmMemoryWipe: Bool

    static let `default` = VaultSettings(defaultZoom: 1.0, confirmMemoryWipe: true)
}

enum ZoomRange {
    static let min = 0.8
    static let max = 1.5
    static let step = 0.1

    static func clamp(_ value: Double) -> Double {
        let stepped = (value * 10).rounded() / 10
        return Swift.min(max, Swift.max(min, stepped))
    }
}
