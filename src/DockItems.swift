import Cocoa
import ApplicationServices

enum DockItemKind: Equatable {
  case app, folder, trash, separator
}

struct DockItem: Equatable {
  let kind: DockItemKind
  let title: String
  let url: URL?
  let isRunning: Bool
  /// The app's badge ("3", "!"), as the Dock shows it; nil when none.
  let badge: String?
  /// The real Dock's element, pressed to mirror a click exactly.
  /// Excluded from equality: elements are recreated as the Dock changes.
  let element: AXUIElement?

  static func == (a: DockItem, b: DockItem) -> Bool {
    a.kind == b.kind && a.title == b.title && a.url == b.url && a.isRunning == b.isRunning && a.badge == b.badge
  }
}

/// What the system Dock shows right now, plus where it sits.
struct DockSnapshot: Equatable {
  var items: [DockItem] = []
  /// The Dock's item list in AX (global, top-left origin) coordinates.
  var frame: CGRect = .zero
}

extension DockReader {
  /// Every Dock item (not only running apps), for the Dock copies.
  static func snapshot() -> DockSnapshot? {
    guard AXIsProcessTrusted(),
          let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
    else { return nil }
    let dockEl = AXUIElementCreateApplication(dock.processIdentifier)
    guard let lists = AX.value(dockEl, kAXChildrenAttribute) as? [AXUIElement],
          let list = lists.first,
          let elements = AX.value(list, kAXChildrenAttribute) as? [AXUIElement]
    else { return nil }

    var snapshot = DockSnapshot(frame: AX.frame(list) ?? .zero)
    for el in elements {
      let subrole = AX.value(el, kAXSubroleAttribute) as? String ?? ""
      let kind: DockItemKind
      switch subrole {
      // Persistent and running apps; "recent" apps are the Dock's
      // suggested-apps section and behave the same when clicked.
      case "AXApplicationDockItem", "AXRecentApplicationDockItem": kind = .app
      case "AXFolderDockItem", "AXFileDockItem", "AXURLDockItem": kind = .folder
      case "AXTrashDockItem": kind = .trash
      case "AXSeparatorDockItem": kind = .separator
      // Minimized windows (AXMinimizedWindowDockItem) are not mirrored:
      // their live thumbnails are not available through AX.
      default: continue
      }
      // Skip a leading/doubled separator left over from skipped items.
      if kind == .separator, snapshot.items.last.map({ $0.kind == .separator }) ?? true { continue }
      snapshot.items.append(DockItem(
        kind: kind,
        title: AX.value(el, kAXTitleAttribute) as? String ?? "",
        url: AX.value(el, kAXURLAttribute) as? URL,
        isRunning: (AX.value(el, "AXIsApplicationRunning") as? NSNumber)?.boolValue ?? false,
        badge: (AX.value(el, "AXStatusLabel") as? String).flatMap { $0.isEmpty ? nil : $0 },
        element: el
      ))
    }
    if snapshot.items.last?.kind == .separator { snapshot.items.removeLast() }
    return snapshot
  }
}

/// Thin wrappers over the AXUIElement C API.
enum AX {
  static func value(_ el: AXUIElement, _ attr: String) -> AnyObject? {
    var v: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
    return v
  }

  static func frame(_ el: AXUIElement) -> CGRect? {
    guard let pos = point(el, kAXPositionAttribute), let size = size(el) else { return nil }
    return CGRect(origin: pos, size: size)
  }

  static func point(_ el: AXUIElement, _ attr: String) -> CGPoint? {
    guard let v = value(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
  }

  static func size(_ el: AXUIElement) -> CGSize? {
    guard let v = value(el, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
  }

  @discardableResult
  static func setPosition(_ el: AXUIElement, _ p: CGPoint) -> Bool {
    var p = p
    guard let v = AXValueCreate(.cgPoint, &p) else { return false }
    return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) == .success
  }

  @discardableResult
  static func setSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
    var s = s
    guard let v = AXValueCreate(.cgSize, &s) else { return false }
    return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) == .success
  }
}
