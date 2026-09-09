import SwiftUI

@main
struct HTMLVaultApp: App {
    @StateObject private var store = VaultFileStore.shared

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
