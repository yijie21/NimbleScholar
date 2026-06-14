import SwiftUI

struct SettingsView: View {
    @AppStorage("nightReading") private var nightReading = false
    @AppStorage("capturePort") private var capturePort = 8781

    var body: some View {
        Form {
            Toggle("Night reading (invert PDF colors)", isOn: $nightReading)
            TextField("Capture server port", value: $capturePort, format: .number)
            Text("Restart required after changing the port.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }
}
