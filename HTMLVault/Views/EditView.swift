import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct EditView: View {
    let app: VaultAppRecord
    @EnvironmentObject var store: VaultFileStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var editor = EditorStore.shared

    @State private var saveOpen = false
    @State private var wipeOnSave = false
    @State private var dangerOpen = false
    @State private var resetOpen = false
    @State private var pickingDraft = false

    var session: EditorSession? { editor.session(for: app.id) }

    var preview: String {
        guard let session else { return "" }
        return EditorEngine.applyMatches(
            src: session.draft,
            matches: session.matches,
            replaceStr: EditorEngine.replacement(mode: session.mode, replace: session.replace)
        )
    }

    var detector: DetectorResult {
        guard let session else {
            return DetectorResult(level: .idle, text: "Damage Detector ready.")
        }
        return EditorEngine.runDetector(
            src: session.draft,
            find: session.find,
            replace: session.replace,
            mode: session.mode,
            matches: session.matches,
            previewResult: preview
        )
    }

    var readyToPush: Bool {
        guard let session else { return false }
        return EditorEngine.canPush(src: session.draft, matches: session.matches, preview: preview)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let session {
                    Picker("Pane", selection: tabBinding) {
                        ForEach(EditTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Group {
                        switch session.tab {
                        case .master: masterPane(session)
                        case .workbench: workbenchPane(session)
                        case .preview: previewPane(session)
                        case .test: testPane(session)
                        }
                    }
                } else {
                    ProgressView("Loading this file’s draft…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("A−") { editor.bumpFont(appId: app.id, delta: -1) }
                    Button("A+") { editor.bumpFont(appId: app.id, delta: 1) }
                    if let session {
                        Text("\(session.editCount) done")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            editor.ensure(appId: app.id, diskText: store.readEntryText(app))
        }
        .id(app.id)
        .fileImporter(isPresented: $pickingDraft, allowedContentTypes: [UTType.html, UTType.text, UTType.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                    editor.setDraft(appId: app.id, draft: text)
                }
            }
        }
        .alert("Damage Detector warning", isPresented: $dangerOpen) {
            Button("Push anyway", role: .destructive) { doPush(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This edit may break the HTML. Push anyway?")
        }
        .alert("Reset draft?", isPresented: $resetOpen) {
            Button("Reset Draft", role: .destructive) {
                editor.resetDraft(appId: app.id, diskText: store.readEntryText(app))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reload this file’s stored bytes into the draft. The library file is not deleted.")
        }
        .sheet(isPresented: $saveOpen) {
            NavigationStack {
                Form {
                    Section {
                        Text("Overwrite this file’s stored bytes with the master draft. Same app id. Other files untouched. Run memory is kept unless you wipe.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle("Also wipe this file’s memory", isOn: $wipeOnSave)
                    }
                    Section {
                        Button("Save Draft Over This File") {
                            store.saveDraftOverFile(app.id, draft: session?.draft ?? "", wipeMemory: wipeOnSave)
                            saveOpen = false
                        }
                    }
                }
                .navigationTitle("Save Draft Over This File")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { saveOpen = false } } }
            }
            .presentationDetents([.medium])
        }
    }

    private var tabBinding: Binding<EditTab> {
        Binding(
            get: { session?.tab ?? .master },
            set: {
                editor.setTab(appId: app.id, tab: $0)
                if $0 == .test { editor.bumpTest(appId: app.id) }
            }
        )
    }

    private func font(_ session: EditorSession) -> Font {
        .system(size: session.fontSize, design: .monospaced)
    }

    @ViewBuilder
    private func masterPane(_ session: EditorSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("MASTER DRAFT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Loaded from this file only. Upload or paste changes the draft, not the library file, until you save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Upload into draft") { pickingDraft = true }
                TextEditor(text: draftBinding)
                    .font(font(session))
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                Text("Master display (last push highlighted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HighlightView(parts: EditorEngine.masterParts(src: session.draft, range: session.lastPushRange), fontSize: session.fontSize)
                HStack {
                    Button("Copy All") { copyDraft(session.draft) }
                    Button("Undo Last Push") { editor.undo(appId: app.id) }
                        .disabled(session.undo.isEmpty)
                    Button("Reset Draft", role: .destructive) { resetOpen = true }
                }
                writeActions
            }
            .padding()
        }
    }

    @ViewBuilder
    private func workbenchPane(_ session: EditorSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("FIND AND ACTION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Mode", selection: modeBinding) {
                    Text("Replace Code").tag(EditMode.replace)
                    Text("Remove Code").tag(EditMode.remove)
                }
                .pickerStyle(.segmented)

                Text("Find Code").font(.caption.weight(.semibold))
                TextEditor(text: findBinding)
                    .font(font(session))
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                Text("Matches found: \(session.matches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.mode == .replace {
                    Text("Replace With").font(.caption.weight(.semibold))
                    TextEditor(text: replaceBinding)
                        .font(font(session))
                        .frame(minHeight: 88)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }

                DetectorBanner(result: detector)

                Text("Each match shows where it is in this file. Uncheck to skip a match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.matches.isEmpty {
                    Text(session.find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "Waiting for search query…"
                         : "No matches found.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(session.matches.enumerated()), id: \.offset) { i, match in
                        matchCard(session: session, match: match, index: i)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func previewPane(_ session: EditorSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("EDIT PREVIEW")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Source text after Push. This is not the Run viewer and does not change the file on disk.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HighlightView(
                    parts: EditorEngine.previewParts(
                        src: session.draft,
                        matches: session.matches,
                        replaceStr: EditorEngine.replacement(mode: session.mode, replace: session.replace),
                        mode: session.mode
                    ),
                    fontSize: session.fontSize
                )
                Button(session.mode == .remove ? "Push Removal Up to Master Draft" : "Push Edit Up to Master Draft") {
                    doPush(force: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.mode == .remove ? .red : .accentColor)
                .disabled(!readyToPush)
                writeActions
            }
            .padding()
        }
    }

    @ViewBuilder
    private func testPane(_ session: EditorSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEST HTML")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Private render of this file’s master draft. Throwaway session. Run still shows the last saved file.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Refresh Edit Preview Page") { editor.bumpTest(appId: app.id) }
                Button("Download Edited File") { shareDraft() }
            }
            DraftWebView(html: session.draft, reloadToken: session.testNonce)
                .frame(maxWidth: .infinity, minHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .id("\(app.id)-edit-test-\(session.testNonce)")
            writeActions
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var writeActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Download Edited File") { shareDraft() }
            Button("Save Draft Over This File") {
                wipeOnSave = false
                saveOpen = true
            }
            Text("Download does not change the library hash. Save overwrites this file only. Back does not save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func matchCard(session: EditorSession, match: EditorMatch, index: Int) -> some View {
        let pos = EditorEngine.getLineCol(session.draft, index: match.index)
        let snip = EditorEngine.snippetAround(src: session.draft, index: match.index, length: match.length)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { match.checked },
                    set: { editor.toggleMatch(appId: app.id, index: index, checked: $0) }
                )) {
                    Text("Match #\(index + 1)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text("Line \(pos.line), Col \(pos.col) (char \(match.index))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Group {
                snippetBlock(label: "Where it is", before: snip.before, match: snip.match, after: snip.after, kind: .find, fontSize: session.fontSize)
                snippetBlock(
                    label: session.mode == .remove ? "After Removal" : "After Replace",
                    before: snip.before,
                    match: session.mode == .remove ? snip.match : session.replace,
                    after: snip.after,
                    kind: session.mode == .remove ? .remove : .replace,
                    fontSize: session.fontSize
                )
            }
            .opacity(match.checked ? 1 : 0.4)
        }
        .padding()
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
    }

    private func snippetBlock(label: String, before: String, match: String, after: String, kind: HighlightKind, fontSize: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HighlightView(
                parts: [
                    HighlightPart(text: before, kind: .plain),
                    HighlightPart(text: match, kind: kind),
                    HighlightPart(text: after, kind: .plain),
                ],
                fontSize: fontSize - 1,
                maxHeight: 120
            )
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { session?.draft ?? "" },
            set: { editor.setDraft(appId: app.id, draft: $0) }
        )
    }

    private var findBinding: Binding<String> {
        Binding(
            get: { session?.find ?? "" },
            set: { editor.setFind(appId: app.id, find: $0) }
        )
    }

    private var replaceBinding: Binding<String> {
        Binding(
            get: { session?.replace ?? "" },
            set: { editor.setReplace(appId: app.id, replace: $0) }
        )
    }

    private var modeBinding: Binding<EditMode> {
        Binding(
            get: { session?.mode ?? .replace },
            set: { editor.setMode(appId: app.id, mode: $0) }
        )
    }

    private func doPush(force: Bool) {
        if detector.level == .danger && !force {
            dangerOpen = true
            return
        }
        _ = editor.push(appId: app.id)
    }

    private func copyDraft(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func shareDraft() {
        let name = "\(app.displayName)-edited.html"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? Data((session?.draft ?? "").utf8).write(to: tmp)
        let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.windows.first { $0.isKeyWindow }?.rootViewController?.present(av, animated: true)
    }
}

struct HighlightView: View {
    let parts: [HighlightPart]
    var fontSize: Double
    var maxHeight: CGFloat = 280

    var body: some View {
        ScrollView {
            Text(attributed)
                .font(.system(size: fontSize, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: maxHeight)
        .padding(8)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        if parts.isEmpty {
            var empty = AttributedString("Empty")
            empty.foregroundColor = .secondary
            return empty
        }
        for part in parts {
            var chunk = AttributedString(part.text)
            switch part.kind {
            case .find:
                chunk.backgroundColor = Color.red.opacity(0.8)
                chunk.foregroundColor = .white
            case .replace, .recent:
                chunk.backgroundColor = Color.green.opacity(0.75)
                chunk.foregroundColor = .white
            case .remove:
                chunk.backgroundColor = Color.pink.opacity(0.75)
                chunk.foregroundColor = .white
                chunk.inlinePresentationIntent = .strikethrough
            case .plain:
                break
            }
            result += chunk
        }
        return result
    }
}

struct DetectorBanner: View {
    let result: DetectorResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DAMAGE DETECTOR")
                .font(.caption.weight(.semibold))
            Text(result.text)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(border, lineWidth: 2)
        )
    }

    private var border: Color {
        switch result.level {
        case .danger: return .red
        case .safe: return .green
        case .warn: return .orange
        case .idle: return .secondary.opacity(0.4)
        }
    }
}
