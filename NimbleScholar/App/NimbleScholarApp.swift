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
                Button("Import PDF…") { importPDFsFromPanel() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
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

/// File ▸ Import PDF…: add one or more local PDFs as new papers. The library refreshes through its
/// GRDB change observation, so no view-model reference is needed here.
private func importPDFsFromPanel() {
    let store = AppEnvironment.shared.store
    let cache = AppEnvironment.shared.downloader.cacheDir
    for url in PDFPicker.pick(allowsMultiple: true, message: "Choose PDF(s) to add to your library") {
        _ = LibraryViewModel.importPDF(at: url, store: store, cache: cache)
    }
}
