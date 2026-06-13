import SwiftUI

/// Deterministic per-tag color (stable across launches), mirroring the old web app.
enum TagColor {
    static func color(for name: String) -> Color {
        var hash = 5381
        for b in name.utf8 { hash = ((hash << 5) &+ hash) &+ Int(b) }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }
}
