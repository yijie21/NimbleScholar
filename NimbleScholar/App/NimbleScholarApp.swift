import SwiftUI
import NimbleScholarCore

@main
struct NimbleScholarApp: App {
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup("Nimble Scholar") {
            LibraryContentView()
                .environmentObject(env)
                .onAppear { env.startCodeWatcherIfNeeded() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    AppEnvironment.shared.updater.checkForUpdates()
                }
            }
            CommandGroup(after: .importExport) {
                Button("Export BibTeX…") { exportBibTeX() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Back Up Library…") { BackupManager.backUp() }
                Button("Restore Library…") { BackupManager.restore() }
            }
        }

        Settings { SettingsView() }
    }
}
