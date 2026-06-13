import SwiftUI
import NimbleScholarCore

// MINIMAL boot version (plan Task 12 / step "C").
// Replaced with the full multi-window App once the UI files land.
@main
struct NimbleScholarApp: App {
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup("Nimble Scholar") {
            BootCheckView().environmentObject(env)
        }
    }
}
