import Foundation

enum DockEdge: String {
  case bottom, left, right
}

/// The system Dock's own settings, read from the `com.apple.dock` defaults
/// domain (the same values System Settings > Desktop & Dock writes).
struct DockPrefs: Equatable {
  var edge = DockEdge.bottom
  /// Icon size in points (`tilesize`; macOS default 48).
  var tileSize: CGFloat = 48
  var autohide = false

  static func read() -> DockPrefs {
    let domain = "com.apple.dock" as CFString
    // The Dock writes these from its own process; drop our cached copy.
    CFPreferencesAppSynchronize(domain)
    var prefs = DockPrefs()
    if let raw = CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String,
       let edge = DockEdge(rawValue: raw) {
      prefs.edge = edge
    }
    if let size = CFPreferencesCopyAppValue("tilesize" as CFString, domain) as? NSNumber {
      prefs.tileSize = CGFloat(truncating: size).clamped(16, 128)
    }
    if let hide = CFPreferencesCopyAppValue("autohide" as CFString, domain) as? NSNumber {
      prefs.autohide = hide.boolValue
    }
    return prefs
  }
}

extension Comparable {
  func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
