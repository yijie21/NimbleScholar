import SwiftUI
import AppKit
import NimbleScholarCore

// FULL app entry (plan step "A"). Swap this in for the minimal NimbleScholarApp.swift:
//   - remove the minimal NimbleScholar/NimbleScholarApp.swift and BootCheckView.swift
//     from the Xcode target,
//   - add this file (App/), plus Library/, Reader/, Settings/.
@main
struct NimbleScholarApp: App {
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup("Nimble Scholar") {
            LibraryContentView().environmentObject(env)
        }
        .commands {
            CommandGroup(after: .importExport) {
                Button("Export BibTeX…") { exportBibTeX() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        // One reader window per paper id.
        WindowGroup("Reader", id: "reader", for: Int64.self) { $paperID in
            ReaderWindow(paperID: paperID).environmentObject(env)
        }

        Settings { SettingsView() }
    }

    private func exportBibTeX() {
        let papers = (try? AppEnvironment.shared.store.allPapers()) ?? []
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "papers.bib"
        if panel.runModal() == .OK, let url = panel.url {
            try? BibTeXExporter.export(papers).data(using: .utf8)?.write(to: url)
        }
    }
}
