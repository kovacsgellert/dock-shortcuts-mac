import Cocoa

/// Dock copies: one copy of the system Dock per other display, kept in sync
/// with the Dock, its settings and the display arrangement. Off unless
/// `dock_copies` is set; idle (no AX reads, no window watching) while off.
final class DockCopies {
  static let shared = DockCopies()

  private var panels: [CGDirectDisplayID: DockCopyPanel] = [:]
  private var snapshot = DockSnapshot()
  private var prefs = DockPrefs()
  private var config = AppConfig.shared
  private var screensKey: [CGRect] = []
  private var dockScreenID: CGDirectDisplayID?
  private let guardian = WindowGuard()
  private var pendingHide: [CGDirectDisplayID: DispatchWorkItem] = [:]

  func start() {
    refresh(force: true)
    NotificationCenter.default.addObserver(forName: .dockChanged, object: nil, queue: .main) { [weak self] _ in
      self?.refresh()
    }
    NotificationCenter.default.addObserver(forName: .appConfigChanged, object: nil, queue: .main) { [weak self] _ in
      self?.refresh(force: true)
    }
    // Everything else arrives as .dockChanged (see DockWatcher), but badge
    // changes and the real Dock hopping displays send no event at all.
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
  }

  func refresh(force: Bool = false) {
    let freshConfig = AppConfig.shared
    guard freshConfig.dockCopies else {
      if config.dockCopies || force { config = freshConfig; removeAll() }
      return
    }
    guard let fresh = DockReader.snapshot() else { return }
    let freshPrefs = DockPrefs.read()
    let freshScreens = NSScreen.screens.map(\.frame)
    let freshDockScreen = Self.screenID(containing: Coords.flip(fresh.frame))
    let changed = force || fresh != snapshot || freshPrefs != prefs || freshConfig != config
      || freshScreens != screensKey || freshDockScreen != dockScreenID
    snapshot = fresh
    guard changed else { return }
    prefs = freshPrefs
    config = freshConfig
    screensKey = freshScreens
    dockScreenID = freshDockScreen
    rebuild()
  }

  private func rebuild() {
    var keep: Set<CGDirectDisplayID> = []
    for screen in NSScreen.screens {
      guard let id = screen.displayID, config.dockCopiesOnDockDisplay || id != dockScreenID else { continue }
      keep.insert(id)
      let layout = DockCopyLayout(items: snapshot.items, prefs: prefs, screen: screen.frame)
      if let panel = panels[id] {
        panel.update(layout: layout, items: snapshot.items)
      } else {
        let panel = DockCopyPanel(screenID: id, layout: layout, items: snapshot.items) { [weak self] item in
          self?.click(item)
        }
        panel.onPointer = { [weak self] inside in self?.pointer(inside: inside, id: id) }
        panels[id] = panel
      }
      panels[id]?.setRevealed(!prefs.autohide, animated: false)
    }
    for (id, panel) in panels where !keep.contains(id) {
      panel.close()
      panels[id] = nil
    }
    // Auto-hidden Docks don't reserve space, same as the real one.
    let reserved = prefs.autohide ? [] : panels.values.map { (edge: $0.layout.edge, rect: $0.layout.reserved) }
    guardian.setReserved(config.dockCopiesKeepWindowsClear ? reserved : [])
  }

  private func removeAll() {
    for panel in panels.values { panel.close() }
    panels.removeAll()
    guardian.setReserved([])
    // Rebuild from scratch when switched back on.
    snapshot = DockSnapshot()
  }

  private func click(_ item: DockItem) {
    switch item.kind {
    case .app:
      // Pressing the real Dock item behaves exactly like a Dock click
      // (launch, activate, un-minimize, bounce).
      if let el = item.element, AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { break }
      if let url = item.url {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
      }
    case .folder:
      // Pressing would pop the stack open on the real Dock's display.
      if let url = item.url { NSWorkspace.shared.open(url) }
    case .trash:
      NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
    case .separator:
      break
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
  }

  /// Auto-hide: reveal when the pointer reaches the copy (only its 1 pt
  /// sliver at the screen edge is on screen while hidden), hide shortly
  /// after it leaves.
  private func pointer(inside: Bool, id: CGDirectDisplayID) {
    guard prefs.autohide, let panel = panels[id] else { return }
    pendingHide.removeValue(forKey: id)?.cancel()
    if inside {
      panel.setRevealed(true)
    } else {
      let work = DispatchWorkItem { [weak panel] in panel?.setRevealed(false) }
      pendingHide[id] = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
  }

  /// The display the real Dock is on: most overlap, else the nearest
  /// (an auto-hidden Dock sits just past the edge), else the main display.
  private static func screenID(containing dock: CGRect) -> CGDirectDisplayID? {
    let screens = NSScreen.screens
    guard !dock.isEmpty else { return screens.first?.displayID }
    func overlap(_ s: NSScreen) -> CGFloat {
      let r = s.frame.intersection(dock)
      return r.isNull ? 0 : r.width * r.height
    }
    func distance(_ s: NSScreen) -> CGFloat {
      hypot(s.frame.midX - dock.midX, s.frame.midY - dock.midY)
    }
    if let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 {
      return best.displayID
    }
    return screens.min(by: { distance($0) < distance($1) })?.displayID
  }
}

extension NSScreen {
  var displayID: CGDirectDisplayID? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }
}
