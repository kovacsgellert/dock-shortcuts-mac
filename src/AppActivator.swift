import Cocoa
import ApplicationServices

enum AppActivator {
  /// Activate the running app matching a Dock item. Returns true on success.
  ///
  /// Multi-window cycling: every press advances to the next window
  /// (wrapping around), continuing from the currently focused/main window
  /// — so releasing Option and pressing Option+N again picks up where
  /// cycling left off instead of restarting at the first window.
  /// Single-window apps keep the old toggle: frontmost -> hide.
  static func activate(_ dockApp: DockApp) -> Bool {
    let running = NSWorkspace.shared.runningApplications
    var target: NSRunningApplication?

    if let bid = dockApp.bundleIdentifier {
      target = running.first { $0.bundleIdentifier == bid }
    }
    if target == nil, let url = dockApp.bundleURL {
      let path = url.path
      target = running.first { $0.bundleURL?.path == path }
    }
    if target == nil {
      target = running.first { $0.localizedName == dockApp.title }
    }
    guard let app = target else { return false }
    let isFinder = app.bundleIdentifier == "com.apple.finder"
    let windows = standardWindows(pid: app.processIdentifier)
    // Multi-window apps: cycle instead of hiding. Every press advances
    // from the currently focused/main window (or, when Accessibility
    // can't see background focus, from the last cycled position), so
    // releasing Option between presses never restarts the cycle.
    if windows.count > 1 {
      let wasActive = app.isActive
      if !wasActive {
        _ = app.activate()
        if isFinder {
          unminimizeWindows(pid: app.processIdentifier)
        }
      }
      cycleToNextWindow(app: app, dockApp: dockApp, windows: windows, advance: wasActive || cycleIndex[appKey(app: app, dockApp: dockApp)] != nil)
      return true
    }
    // Single-window (or windowless) apps: toggle hide / activate.
    // If frontmost *with visible windows*, hide it (toggle). Otherwise
    // activate — and for Finder, restore minimized windows and open a new
    // one if there are none, mirroring a Dock click.
    if app.isActive, !isFinder || hasVisibleWindows(pid: app.processIdentifier) {
      app.hide()
    } else {
      _ = app.activate()
      if isFinder {
        unminimizeWindows(pid: app.processIdentifier)
        if finderWindowCount(pid: app.processIdentifier) == 0 {
          NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
        }
      }
    }
    return true
  }

  /// Real windows (role AXWindow), excluding exposed non-windows.
  /// AXWindows is ordered front-to-back, so index 0 is the frontmost.
  private static func standardWindows(pid: pid_t) -> [AXUIElement] {
    let finder = AXUIElementCreateApplication(pid)
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(finder, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement]
    else { return [] }
    return windows.filter { w in
      var role: AnyObject?
      AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &role)
      return (role as? String) == "AXWindow"
    }
  }

  private static func isMinimized(_ w: AXUIElement) -> Bool {
    var v: AnyObject?
    AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &v)
    return (v as? NSNumber)?.boolValue == true
  }

  private static func hasVisibleWindows(pid: pid_t) -> Bool {
    standardWindows(pid: pid).contains { !isMinimized($0) }
  }

  private static func unminimizeWindows(pid: pid_t) {
    for w in standardWindows(pid: pid) where isMinimized(w) {
      AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
      AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }
  }

  /// Number of real windows via Accessibility (no extra permission needed).
  private static func finderWindowCount(pid: pid_t) -> Int {
    standardWindows(pid: pid).count
  }

  // MARK: - Window cycling

  /// Stable rotation per app. AXWindows re-sorts itself (the main window
  /// comes back at index 0), so plain index+1 cycling ping-pongs between
  /// two windows and never reaches the rest. Instead we keep our own
  /// window order and advance within it; AXUIElement identity (CFEqual)
  /// is stable across fetches, so the rotation survives re-sorting.
  private static var cycleOrder: [String: [AXUIElement]] = [:]
  private static var cycleIndex: [String: Int] = [:]

  /// Stable per-app key: bundle id wins, then bundle path, then title.
  private static func appKey(app: NSRunningApplication, dockApp: DockApp) -> String {
    if let bid = app.bundleIdentifier ?? dockApp.bundleIdentifier { return "bid:\(bid)" }
    let path = app.bundleURL?.path ?? dockApp.bundleURL?.path
    if let path { return "path:\(path)" }
    if let name = app.localizedName ?? dockApp.title as String? { return "name:\(name)" }
    return "pid:\(app.processIdentifier)"
  }

  /// Focus the next window in the app's stable rotation, wrapping around.
  /// - When the current focused/main window is readable: advance from its
  ///   position in the stable order, unless this is the very first touch
  ///   of an inactive app (no history), in which case keep the current
  ///   window instead of skipping past it.
  /// - When unreadable (typical for background apps): advance from the
  ///   last cycled position, else start at the frontmost window.
  /// New windows join the end of the rotation; closed ones drop out.
  private static func cycleToNextWindow(app: NSRunningApplication, dockApp: DockApp, windows: [AXUIElement], advance: Bool) {
    let key = appKey(app: app, dockApp: dockApp)
    var order = cycleOrder[key]?.filter { kept in windows.contains(where: { CFEqual(kept, $0) }) } ?? []
    for w in windows where !order.contains(where: { CFEqual($0, w) }) {
      order.append(w)
    }
    guard !order.isEmpty else { return }
    func position(of window: AXUIElement) -> Int? {
      order.firstIndex(where: { CFEqual($0, window) })
    }
    let next: Int
    if let current = focusedWindowIndex(windows: windows),
       let pos = position(of: windows[current]) {
      next = advance ? (pos + 1) % order.count : pos
    } else if let last = cycleIndex[key] {
      next = (last + 1) % order.count
    } else {
      next = 0
    }
    cycleOrder[key] = order
    cycleIndex[key] = next
    focusWindow(app: app, window: order[next])
  }

  /// Index of the window carrying keyboard focus (focused, else main).
  private static func focusedWindowIndex(windows: [AXUIElement]) -> Int? {
    for (i, w) in windows.enumerated() {
      var v: AnyObject?
      if AXUIElementCopyAttributeValue(w, kAXFocusedAttribute as CFString, &v) == .success,
         (v as? NSNumber)?.boolValue == true {
        return i
      }
    }
    for (i, w) in windows.enumerated() {
      var v: AnyObject?
      if AXUIElementCopyAttributeValue(w, kAXMainAttribute as CFString, &v) == .success,
         (v as? NSNumber)?.boolValue == true {
        return i
      }
    }
    return nil
  }

  /// Bring one window of an already-resolved app to the front with focus.
  private static func focusWindow(app: NSRunningApplication, window: AXUIElement) {
    _ = app.activate()
    if isMinimized(window) {
      AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    // Raise alone may leave keyboard focus behind — re-assert activation.
    _ = app.activate()
  }
}
