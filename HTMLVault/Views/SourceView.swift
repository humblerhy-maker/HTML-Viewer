import SwiftUI

struct SourceView: View {
    let app: VaultAppRecord
    @EnvironmentObject var store: VaultFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var running = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(store.readEntryText(app))
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run this file") {
                        store.markOpened(app.id)
                        running = true
                    }
                }
            }
            .fullScreenCover(isPresented: $running) {
                RunView(appId: app.id)
            }
        }
    }
}
