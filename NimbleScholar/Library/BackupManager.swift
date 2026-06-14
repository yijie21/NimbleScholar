import AppKit
import UniformTypeIdentifiers

/// Backs up / restores the whole data directory (SQLite DB + cached PDFs) as a zip via `ditto`.
enum BackupManager {
    /// ~/Library/Application Support/Nimble Scholar
    private static var dataDir: URL {
        (try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true))
            .appendingPathComponent("Nimble Scholar", isDirectory: true)
    }

    static func backUp() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NimbleScholar-Backup.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", dataDir.path, dest.path])
    }

    static func restore() {
        let confirm = NSAlert()
        confirm.messageText = "Restore from backup?"
        confirm.informativeText = "This replaces your current library with the backup. The app will quit; reopen it afterward."
        confirm.addButton(withTitle: "Choose Backup…")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let open = NSOpenPanel()
        open.allowedContentTypes = [.zip]
        guard open.runModal() == .OK, let zip = open.url else { return }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ns-restore-\(UUID().uuidString)")
        run(["/usr/bin/ditto", "-x", "-k", zip.path, tmp.path])
        // `--keepParent` nested the contents under a "Nimble Scholar" folder.
        let nested = tmp.appendingPathComponent("Nimble Scholar")
        let src = FileManager.default.fileExists(atPath: nested.path) ? nested : tmp
        try? FileManager.default.removeItem(at: dataDir)
        try? FileManager.default.moveItem(at: src, to: dataDir)
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }
}
