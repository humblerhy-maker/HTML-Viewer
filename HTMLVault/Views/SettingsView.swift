import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: VaultFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var resetOpen = false
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Default zoom for new files") {
                    HStack {
                        Button("A−") {
                            store.settings.defaultZoom = ZoomRange.clamp(store.settings.defaultZoom - ZoomRange.step)
                            store.save()
                        }
                        Spacer()
                        Text("\(Int(store.settings.defaultZoom * 100))%")
                            .font(.body.monospacedDigit())
                        Spacer()
                        Button("A+") {
                            store.settings.defaultZoom = ZoomRange.clamp(store.settings.defaultZoom + ZoomRange.step)
                            store.save()
                        }
                    }
                    Text("Range 80%–150%, steps of 10%. Manual only. Pinch-zoom of a running page is off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Toggle("Confirm before memory wipe", isOn: Binding(
                    get: { store.settings.confirmMemoryWipe },
                    set: { store.settings.confirmMemoryWipe = $0; store.save() }
                ))
                Section {
                    Text("HTML Viewer never modifies your HTML. Source is the exact stored bytes. No account, no analytics, no third-party SDK except Apple.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Reset entire vault", role: .destructive) { resetOpen = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
            .alert("Reset entire vault", isPresented: $resetOpen) {
                TextField("RESET ENTIRE VAULT", text: $typed)
                Button("Reset entire vault", role: .destructive) {
                    if typed == "RESET ENTIRE VAULT" {
                        store.resetEntireVault()
                    }
                    typed = ""
                }
                Button("Cancel", role: .cancel) { typed = "" }
            } message: {
                Text("This removes every file from the library. Type RESET ENTIRE VAULT to continue.")
            }
        }
    }
}
