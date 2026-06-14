import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ReadingSettings()
                .tabItem { Label("Reading", systemImage: "book") }
        }
        .frame(width: 460)
    }
}

private struct GeneralSettings: View {
    @AppStorage("defaultCaptureTags") private var defaultTags = "to-read"
    @AppStorage("capturePort") private var capturePort = 8917

    private var boundPort: String {
        (try? String(contentsOfFile: "/tmp/nimblescholar-port.txt", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "—"
    }

    var body: some View {
        Form {
            Section("Capture") {
                TextField("Default tags for new captures", text: $defaultTags)
                Text("Comma-separated. Applied when you capture a paper without specifying tags.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Capture server") {
                TextField("Preferred port", value: $capturePort, format: .number)
                LabeledContent("Currently listening on", value: boundPort)
                Text("The browser extension finds the app automatically. Change the port only if it conflicts; restart the app to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }
}

private struct ReadingSettings: View {
    @AppStorage("nightReading") private var nightReading = false
    @AppStorage("highlightColorHex") private var highlightColorHex = "#ffd966"

    private let colors: [(name: String, hex: String)] = [
        ("Yellow", "#ffd966"), ("Green", "#a8e6a1"), ("Blue", "#9ec9ff"),
        ("Pink", "#ffb3d1"), ("Orange", "#ffc08a"),
    ]

    var body: some View {
        Form {
            Section("PDF reader") {
                Toggle("Night reading (invert PDF colors)", isOn: $nightReading)
            }
            Section("Highlight color") {
                HStack(spacing: 12) {
                    ForEach(colors, id: \.hex) { c in
                        Circle()
                            .fill(Color(hex: c.hex))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: highlightColorHex == c.hex ? 2.5 : 0))
                            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                            .onTapGesture { highlightColorHex = c.hex }
                            .help(c.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }
}
