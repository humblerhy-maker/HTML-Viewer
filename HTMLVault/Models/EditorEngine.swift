import Foundation

enum EditMode: String {
    case replace
    case remove
}

enum EditTab: String, CaseIterable, Identifiable {
    case master
    case workbench
    case preview
    case test
    var id: String { rawValue }
    var title: String {
        switch self {
        case .master: return "Master"
        case .workbench: return "Edit"
        case .preview: return "Preview"
        case .test: return "Test HTML"
        }
    }
}

enum DetectorLevel {
    case idle, warn, danger, safe
}

struct EditorMatch: Identifiable, Equatable {
    var id: Int { index }
    var index: Int
    var length: Int
    var originalText: String
    var checked: Bool
}

struct PushRange: Equatable {
    var start: Int
    var length: Int
}

struct UndoFrame {
    var source: String
    var count: Int
    var range: PushRange?
}

struct DetectorResult {
    var level: DetectorLevel
    var text: String
}

enum HighlightKind {
    case plain, find, replace, remove, recent
}

struct HighlightPart {
    var text: String
    var kind: HighlightKind
}

struct EditorSession {
    var appId: UUID
    var draft: String
    var find: String
    var replace: String
    var mode: EditMode
    var tab: EditTab
    var matches: [EditorMatch]
    var undo: [UndoFrame]
    var editCount: Int
    var lastPushRange: PushRange?
    var fontSize: Double
    var testNonce: Int

    static func empty(appId: UUID, draft: String) -> EditorSession {
        EditorSession(
            appId: appId,
            draft: draft,
            find: "",
            replace: "",
            mode: .replace,
            tab: .master,
            matches: [],
            undo: [],
            editCount: 0,
            lastPushRange: nil,
            fontSize: 16,
            testNonce: 1
        )
    }
}

enum EditorEngine {
    static func clampFont(_ n: Double) -> Double {
        min(22, max(16, n))
    }

    static func getSmartRegex(_ findStr: String) -> NSRegularExpression? {
        let tokens = findStr
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !tokens.isEmpty else { return nil }
        let pattern = tokens.joined(separator: "[\\s\\n\\r\\t]*")
        return try? NSRegularExpression(pattern: pattern, options: [])
    }

    static func getLineCol(_ src: String, index: Int) -> (line: Int, col: Int) {
        let ns = src as NSString
        let clamped = max(0, min(index, ns.length))
        let before = ns.substring(to: clamped)
        let lines = before.split(separator: "\n", omittingEmptySubsequences: false)
        let col = (lines.last?.count ?? 0) + 1
        return (lines.count, col)
    }

    static func findMatches(src: String, find: String) -> [EditorMatch] {
        guard !src.isEmpty, !find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let regex = getSmartRegex(find) else { return [] }
        let ns = src as NSString
        let found = regex.matches(in: src, options: [], range: NSRange(location: 0, length: ns.length))
        return found.map { match in
            EditorMatch(
                index: match.range.location,
                length: match.range.length,
                originalText: ns.substring(with: match.range),
                checked: true
            )
        }
    }

    static func replacement(mode: EditMode, replace: String) -> String {
        mode == .remove ? "" : replace
    }

    static func applyMatches(src: String, matches: [EditorMatch], replaceStr: String) -> String {
        if src.isEmpty || matches.isEmpty { return src }
        let ns = src as NSString
        var raw = ""
        var pos = 0
        for match in matches {
            if match.index > pos {
                raw += ns.substring(with: NSRange(location: pos, length: match.index - pos))
            }
            raw += match.checked ? replaceStr : match.originalText
            pos = match.index + match.length
        }
        if pos < ns.length {
            raw += ns.substring(from: pos)
        }
        return raw
    }

    static func previewParts(src: String, matches: [EditorMatch], replaceStr: String, mode: EditMode) -> [HighlightPart] {
        if src.isEmpty { return [] }
        if matches.isEmpty { return [HighlightPart(text: src, kind: .plain)] }
        let ns = src as NSString
        var parts: [HighlightPart] = []
        var pos = 0
        for match in matches {
            if match.index > pos {
                parts.append(HighlightPart(
                    text: ns.substring(with: NSRange(location: pos, length: match.index - pos)),
                    kind: .plain
                ))
            }
            if !match.checked {
                parts.append(HighlightPart(text: match.originalText, kind: .plain))
            } else if mode == .remove {
                parts.append(HighlightPart(text: match.originalText, kind: .remove))
            } else {
                parts.append(HighlightPart(text: replaceStr, kind: .replace))
            }
            pos = match.index + match.length
        }
        if pos < ns.length {
            parts.append(HighlightPart(text: ns.substring(from: pos), kind: .plain))
        }
        return parts
    }

    static func masterParts(src: String, range: PushRange?) -> [HighlightPart] {
        if src.isEmpty { return [] }
        guard let range, range.start >= 0, range.start <= (src as NSString).length, range.length > 0 else {
            return [HighlightPart(text: src, kind: .plain)]
        }
        let ns = src as NSString
        var parts: [HighlightPart] = []
        if range.start > 0 {
            parts.append(HighlightPart(text: ns.substring(to: range.start), kind: .plain))
        }
        let end = min(range.start + range.length, ns.length)
        if end > range.start {
            parts.append(HighlightPart(
                text: ns.substring(with: NSRange(location: range.start, length: end - range.start)),
                kind: .recent
            ))
        }
        if end < ns.length {
            parts.append(HighlightPart(text: ns.substring(from: end), kind: .plain))
        }
        return parts
    }

    static func snippetAround(src: String, index: Int, length: Int, radius: Int = 100) -> (before: String, match: String, after: String) {
        let ns = src as NSString
        let start = max(0, index - radius)
        let end = min(ns.length, index + length + radius)
        var before = ns.substring(with: NSRange(location: start, length: max(0, index - start)))
        var after = ns.substring(with: NSRange(location: index + length, length: max(0, end - (index + length))))
        if start > 0 { before = "..." + before }
        if end < ns.length { after += "..." }
        let match = ns.substring(with: NSRange(location: index, length: min(length, ns.length - index)))
        return (before, match, after)
    }

    static func runDetector(
        src: String,
        find: String,
        replace: String,
        mode: EditMode,
        matches: [EditorMatch],
        previewResult: String
    ) -> DetectorResult {
        if src.isEmpty || find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DetectorResult(level: .idle, text: "Damage Detector ready. Type Find/Replace to see safety check.")
        }
        if mode == .replace && find == replace && !find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DetectorResult(level: .warn, text: "Same code in Find and Replace — this edit does nothing.")
        }
        if matches.isEmpty {
            return DetectorResult(level: .warn, text: "No matches found. Nothing will change if you push.")
        }
        let critical = ["<html", "<head", "<body", "</html", "</head", "</body"]
        let lowerSrc = src.lowercased()
        let lowerPreview = previewResult.lowercased()
        let lost = critical.filter { lowerSrc.contains($0) && !lowerPreview.contains($0) }
        if !lost.isEmpty {
            return DetectorResult(
                level: .danger,
                text: "DANGER: Edit removes critical tags: \(lost.joined(separator: ", ")). This will break your file!"
            )
        }
        let findOpen = find.filter { $0 == "<" }.count
        let findClose = find.filter { $0 == ">" }.count
        if mode == .replace {
            let repOpen = replace.filter { $0 == "<" }.count
            let repClose = replace.filter { $0 == ">" }.count
            if findOpen != findClose || repOpen != repClose {
                return DetectorResult(level: .warn, text: "Unbalanced angle brackets in Find or Replace — verify carefully before pushing.")
            }
        } else if findOpen != findClose {
            return DetectorResult(level: .warn, text: "Unbalanced angle brackets in Find — removal may damage structure.")
        }
        if find.filter({ $0 == "\"" }).count % 2 != 0 {
            return DetectorResult(level: .warn, text: "Odd number of quotes in Find — may match too much. Verify before pushing.")
        }
        let checked = matches.filter(\.checked).count
        let action = mode == .remove ? "remove" : "replace"
        return DetectorResult(
            level: .safe,
            text: "Safe to push. Will \(action) \(checked) match\(checked == 1 ? "" : "es"). HTML structure looks balanced."
        )
    }

    static func canPush(src: String, matches: [EditorMatch], preview: String) -> Bool {
        matches.contains(where: \.checked) && preview != src
    }
}
