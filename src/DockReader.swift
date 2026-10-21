import Cocoa
import ApplicationServices

struct DockApp: Equatable {
  let index: Int // 1-based number shown to user
  let title: String
  let bundleURL: URL?
  let frame: CGRect
  var bundleIdentifier: String? {
    guard let url = bundleURL else { return nil }
    return Bundle(url: url)?.bundleIdentifier
  }
}

enum DockReader {
  static func runningAppItems() -> [DockApp] {
    guard AXIsProcessTrusted() else {
      fputs("ERROR: no Accessibility permission. Enable in System Settings > Privacy & Security > Accessibility.\n", stderr)
      return []
    }
    guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
      fputs("ERROR: Dock process not found\n", stderr)
      return []
    }
    let dockEl = AXUIElementCreateApplication(dock.processIdentifier)
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(dockEl, kAXChildrenAttribute as CFString, &children) == .success,
          let lists = children as? [AXUIElement],
          let list = lists.first else { return [] }
    var itemsRaw: AnyObject?
    guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &itemsRaw) == .success,
          let items = itemsRaw as? [AXUIElement] else { return [] }

    var out: [DockApp] = []
    for el in items {
      var subrole: AnyObject?
      AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subrole)
      guard (subrole as? String) == "AXApplicationDockItem" else { continue }

      var running: AnyObject?
      AXUIElementCopyAttributeValue(el, "AXIsApplicationRunning" as CFString, &running)
      guard (running as? NSNumber)?.boolValue == true else { continue }

      var titleV: AnyObject?
      AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleV)
      let title = (titleV as? String) ?? "?"

      var urlV: AnyObject?
      AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlV)
      let url = urlV as? URL

      var frame = CGRect.zero
      var frameV: AnyObject?
      if AXUIElementCopyAttributeValue(el, "AXFrame" as CFString, &frameV) == .success,
         let v = frameV, CFGetTypeID(v) == AXValueGetTypeID() {
        let axv = v as! AXValue
        var r = CGRect.zero
        if AXValueGetValue(axv, .cgRect, &r) { frame = unmirrored(r) }
      }
      out.append(DockApp(index: out.count + 1, title: title, bundleURL: url, frame: frame))
    }
    return out
  }

  /// macOS 27 reports the items of a left-side Dock mirrored around x = 0
  /// (x = -(real maxX)), i.e. off every screen. Flip such frames back when
  /// the mirror lands on a screen. Not for an auto-hidden Dock, whose items
  /// really are off screen while hidden.
  private static func unmirrored(_ frame: CGRect) -> CGRect {
    let screens = NSScreen.screens.map { Coords.flip($0.frame) }
    guard !screens.contains(where: { $0.intersects(frame) }), !DockPrefs.read().autohide else { return frame }
    let mirror = CGRect(x: -frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    return screens.contains(where: { $0.intersects(mirror) }) ? mirror : frame
  }
}
