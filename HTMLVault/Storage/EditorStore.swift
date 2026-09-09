import Foundation

@MainActor
final class EditorStore: ObservableObject {
    static let shared = EditorStore()

    @Published var byId: [UUID: EditorSession] = [:]

    private init() {}

    func session(for id: UUID) -> EditorSession? {
        byId[id]
    }

    func ensure(appId: UUID, diskText: String) {
        if byId[appId] == nil {
            byId[appId] = .empty(appId: appId, draft: diskText)
        }
    }

    private func refreshMatches(_ session: EditorSession) -> EditorSession {
        var next = session
        next.matches = EditorEngine.findMatches(src: session.draft, find: session.find)
        return next
    }

    func setDraft(appId: UUID, draft: String) {
        guard var current = byId[appId] else { return }
        current.draft = draft
        current.lastPushRange = nil
        byId[appId] = refreshMatches(current)
    }

    func setFind(appId: UUID, find: String) {
        guard var current = byId[appId] else { return }
        current.find = find
        byId[appId] = refreshMatches(current)
    }

    func setReplace(appId: UUID, replace: String) {
        guard var current = byId[appId] else { return }
        current.replace = replace
        byId[appId] = current
    }

    func setMode(appId: UUID, mode: EditMode) {
        guard var current = byId[appId] else { return }
        current.mode = mode
        byId[appId] = current
    }

    func setTab(appId: UUID, tab: EditTab) {
        guard var current = byId[appId] else { return }
        current.tab = tab
        byId[appId] = current
    }

    func toggleMatch(appId: UUID, index: Int, checked: Bool) {
        guard var current = byId[appId], current.matches.indices.contains(index) else { return }
        current.matches[index].checked = checked
        byId[appId] = current
    }

    @discardableResult
    func push(appId: UUID) -> Bool {
        guard let current = byId[appId] else { return false }
        let replaceStr = EditorEngine.replacement(mode: current.mode, replace: current.replace)
        let nextDraft = EditorEngine.applyMatches(src: current.draft, matches: current.matches, replaceStr: replaceStr)
        if nextDraft == current.draft { return false }
        let firstChecked = current.matches.first(where: \.checked)
        let lastPushRange: PushRange? = {
            guard let firstChecked, !replaceStr.isEmpty else { return nil }
            return PushRange(start: firstChecked.index, length: (replaceStr as NSString).length)
        }()
        var undo = current.undo
        undo.append(UndoFrame(source: current.draft, count: current.editCount, range: current.lastPushRange))
        if undo.count > 50 { undo.removeFirst(undo.count - 50) }
        var next = current
        next.undo = undo
        next.draft = nextDraft
        next.find = ""
        next.replace = ""
        next.matches = []
        next.editCount = current.editCount + 1
        next.lastPushRange = lastPushRange
        byId[appId] = next
        return true
    }

    func undo(appId: UUID) {
        guard var current = byId[appId], let last = current.undo.popLast() else { return }
        current.draft = last.source
        current.editCount = last.count
        current.lastPushRange = last.range
        byId[appId] = refreshMatches(current)
    }

    func resetDraft(appId: UUID, diskText: String) {
        guard let current = byId[appId] else { return }
        var next = EditorSession.empty(appId: appId, draft: diskText)
        next.tab = current.tab
        next.fontSize = current.fontSize
        byId[appId] = next
    }

    func bumpFont(appId: UUID, delta: Double) {
        guard var current = byId[appId] else { return }
        current.fontSize = EditorEngine.clampFont(current.fontSize + delta)
        byId[appId] = current
    }

    func bumpTest(appId: UUID) {
        guard var current = byId[appId] else { return }
        current.testNonce += 1
        byId[appId] = current
    }

    func drop(_ appId: UUID) {
        byId.removeValue(forKey: appId)
    }

    func dropAll() {
        byId.removeAll()
    }
}
