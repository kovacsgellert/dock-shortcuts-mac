import Foundation

/// Portable settings in ~/.config/dock-shortcuts/config.yml (XDG-style).
/// Hand- and script-editable; the app applies them at launch and reloads
/// them when the settings window opens. No third-party YAML dependency:
/// the format is flat `key: value` pairs, parsed below.
struct AppConfig: Equatable {
  var startAtLogin = false
  var showMenuBarIcon = true
  var appearance = AppAppearance.system
  /// Badge show delay in milliseconds, clamped to 0...500.
  var badgeDelayMs = 100
  /// Persistent mini-badges on Dock icons (no Option hold needed).
  var badgesAlwaysVisible = false
  /// Copy the Dock onto every display the real Dock isn't on.
  var dockCopies = false
  /// Also copy it onto the real Dock's display (on top of the Dock).
  var dockCopiesOnDockDisplay = false
  /// Shrink zoomed/tiled windows out of the copies' area.
  var dockCopiesKeepWindowsClear = true

  /// XDG_CONFIG_HOME when set (absolute, ~ expanded), else ~/.config.
  /// macOS has no XDG convention natively, but this keeps dotfile-managed
  /// setups and scripts portable across machines.
  static let dirURL: URL = {
    if var xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
       !xdg.trimmingCharacters(in: .whitespaces).isEmpty {
      xdg = (xdg as NSString).expandingTildeInPath
      return URL(fileURLWithPath: xdg, isDirectory: true)
        .appendingPathComponent("dock-shortcuts", isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/dock-shortcuts", isDirectory: true)
  }()

  static let fileURL: URL = dirURL.appendingPathComponent("config.yml")

  /// Previous location (pre-rename). Migrated once if the new file is missing.
  private static let legacyFileURL: URL = {
    if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
       !(xdg.trimmingCharacters(in: .whitespaces).isEmpty) {
      return URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath, isDirectory: true)
        .appendingPathComponent("dock-numbers/config.yml")
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/dock-numbers/config.yml")
  }()

  /// Live copy used across the app. Mutate then save(), or reload() from disk.
  static var shared = load()

  mutating func reload() {
    self = Self.load()
  }

  // MARK: - Load / save

  static func load() -> AppConfig {
    // One-time rename migration.
    if !FileManager.default.fileExists(atPath: fileURL.path),
       FileManager.default.fileExists(atPath: legacyFileURL.path) {
      try? FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try? FileManager.default.copyItem(at: legacyFileURL, to: fileURL)
    }
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
      // First run (or deleted file): migrate legacy UserDefaults, then persist.
      var fresh = AppConfig()
      fresh.startAtLogin = LaunchAtLogin.isEnabled
      if let v = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool {
        fresh.showMenuBarIcon = v
      }
      if let raw = UserDefaults.standard.string(forKey: "appearance"),
         let a = AppAppearance(rawValue: raw) {
        fresh.appearance = a
      }
      fresh.save()
      return fresh
    }
    var config = AppConfig()
    let dict = parse(text)
    var missingKeys = false
    func take(_ key: String) -> String? {
      guard let v = dict[key] else { missingKeys = true; return nil }
      return v
    }
    if let raw = take("start_at_login"), let b = parseBool(raw) {
      config.startAtLogin = b
    }
    if let raw = take("show_menu_bar_icon"), let b = parseBool(raw) {
      config.showMenuBarIcon = b
    }
    if let raw = take("appearance"), let a = AppAppearance(rawValue: raw.lowercased()) {
      config.appearance = a
    }
    if let raw = take("badge_delay_ms"), let ms = Int(raw) {
      config.badgeDelayMs = min(max(ms, 0), 500)
    }
    if let raw = take("badges_always_visible"), let b = parseBool(raw) {
      config.badgesAlwaysVisible = b
    }
    if let raw = take("dock_copies"), let b = parseBool(raw) {
      config.dockCopies = b
    }
    if let raw = take("dock_copies_on_dock_display"), let b = parseBool(raw) {
      config.dockCopiesOnDockDisplay = b
    }
    if let raw = take("dock_copies_keep_windows_clear"), let b = parseBool(raw) {
      config.dockCopiesKeepWindowsClear = b
    }
    // Older files predate newer keys: backfill once so the file always
    // documents every setting (and hand-editing discovery works).
    if missingKeys {
      config.save()
    }
    return config
  }

  func save() {
    let text = """
      # dock-shortcuts settings — portable, safe to edit by hand or scripts.
      # Regenerated only when missing; your edits are preserved.
      start_at_login: \(startAtLogin)
      show_menu_bar_icon: \(showMenuBarIcon)
      appearance: \(appearance.rawValue)  # system | light | dark
      badge_delay_ms: \(badgeDelayMs)  # 0...500
      badges_always_visible: \(badgesAlwaysVisible)
      dock_copies: \(dockCopies)  # copy the Dock onto your other displays
      dock_copies_on_dock_display: \(dockCopiesOnDockDisplay)
      dock_copies_keep_windows_clear: \(dockCopiesKeepWindowsClear)

      """
    do {
      try FileManager.default.createDirectory(
        at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try text.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    } catch {
      NSLog("DockShortcuts: couldn't save config: \(error)")
    }
  }

  // MARK: - Minimal flat-YAML parsing

  private static func parse(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    for line in text.components(separatedBy: .newlines) {
      let t = line.trimmingCharacters(in: .whitespaces)
      guard !t.isEmpty, !t.hasPrefix("#") else { continue }
      let parts = t.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { continue }
      var value = parts[1].trimmingCharacters(in: .whitespaces)
      if let range = value.range(of: " #") {
        value = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
      }
      out[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = value
    }
    return out
  }

  private static func parseBool(_ raw: String) -> Bool? {
    switch raw.lowercased() {
    case "true", "yes", "on", "1": return true
    case "false", "no", "off", "0": return false
    default: return nil
    }
  }
}

extension Notification.Name {
  /// Posted when settings change via the window (file watcher tick also applies hand edits).
  static let appConfigChanged = Notification.Name("dock-shortcuts.configChanged")
}
