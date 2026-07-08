import SwiftUI

/// Lets menu commands reach the library window's view model.
struct LibraryVMFocusedKey: FocusedValueKey {
    typealias Value = LibraryViewModel
}
extension FocusedValues {
    var libraryVM: LibraryViewModel? {
        get { self[LibraryVMFocusedKey.self] }
        set { self[LibraryVMFocusedKey.self] = newValue }
    }
}

/// The Paper menu: open the reader, step through papers while reading, night mode.
/// Actions no-op (rather than disable) when no library window is focused — menu
/// enablement can't observe @Published state reliably.
struct PaperCommands: Commands {
    @FocusedValue(\.libraryVM) private var vm
    @AppStorage("nightReading") private var nightReading = false

    var body: some Commands {
        CommandMenu("Paper") {
            Button("Read Paper") { vm?.openSelectedInReader() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Next Paper") { vm?.stepPaper(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Paper") { vm?.stepPaper(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Divider()
            Toggle("Night Reading", isOn: $nightReading)
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
    }
}
