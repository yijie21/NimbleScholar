import Foundation
import Sparkle

/// Owns the Sparkle updater. Created once (held by `AppEnvironment`) so the
/// "Check for Updates…" menu item and the Settings toggle share one instance.
///
/// Must be constructed on the main thread (it is — `AppEnvironment.shared` is first
/// realized by the app's `@StateObject` at launch).
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true → begin scheduled background checks immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Show Sparkle's update UI (menu item / "Check Now" button).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Whether Sparkle performs automatic background checks (bound to the Settings toggle).
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }
}
