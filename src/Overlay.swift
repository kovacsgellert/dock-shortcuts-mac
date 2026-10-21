import Cocoa

/// Which screen edge the Dock sits on. Badges go on the screen-center side.
enum DockSide {
  case left, right, bottom, top

  init(_ edge: DockEdge) {
    switch edge {
    case .left: self = .left
    case .right: self = .right
    case .bottom: self = .bottom
    }
  }
}

private final class GlassBadgeView: NSVisualEffectView {
  init(diameter: CGFloat, text: String, dark: Bool) {
    super.init(frame: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))
    // Dark: translucent-dark glass; light: frosted-light glass.
    material = dark ? .hudWindow : .popover
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = diameter / 2
    layer?.masksToBounds = true
    layer?.borderColor = NSColor.white.withAlphaComponent(dark ? 0.5 : 0.7).cgColor
    layer?.borderWidth = 1

    // Top-down specular gloss: the "liquid" cue.
    let gloss = CAGradientLayer()
    gloss.colors = [
      NSColor.white.withAlphaComponent(dark ? 0.28 : 0.5).cgColor,
      NSColor.white.withAlphaComponent(0.0).cgColor,
    ]
    gloss.startPoint = CGPoint(x: 0.5, y: 0.0)
    gloss.endPoint = CGPoint(x: 0.5, y: 1.0)
    gloss.frame = bounds
    gloss.cornerRadius = diameter / 2
    layer?.addSublayer(gloss)

    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: (diameter * 0.53).rounded(), weight: .semibold)
    label.textColor = dark ? .white : .black
    label.alignment = .center
    // Vertically true-center: NSTextField doesn't center text within an
    // oversized frame, so center the field itself (intrinsic height) instead.
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
    ])
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError() }
}

private extension NSShadow {
  func withConfigured(color: NSColor, blur: CGFloat, offset: CGSize) -> NSShadow {
    let s = NSShadow()
    s.shadowColor = color
    s.shadowBlurRadius = blur
    s.shadowOffset = offset
    return s
  }
}

/// Floating number badges beside Dock icons.
/// AX frames use a top-left origin; Cocoa windows use bottom-left, so we flip Y.
/// Badge presentation style.
enum BadgeStyle {
  /// Option-hold: large badges beside icons, toward the screen center.
  case hold
  /// Always-visible: small badges inset in the icon's top-left corner,
  /// fully inside the Dock perimeter.
  case persistent
}

final class OverlayManager {
  private var panels: [NSPanel] = []
  /// What the panels currently show (nil = hidden). Lets the watcher tell
  /// a hold overlay apart from persistent mini-badges.
  private(set) var styleShown: BadgeStyle?
  private let holdSize: CGFloat = 28
  private let persistentSize: CGFloat = 20
  /// Inset of persistent badges from the icon corner (keeps them on the icon).
  private let cornerInset: CGFloat = 2
  private let gap: CGFloat = 8

  @MainActor
  func show(apps: [DockApp], style: BadgeStyle = .hold) {
    hide()
    guard let screen = NSScreen.screens.first else { return }
    let dark = AppAppearance.isDark
    let diameter = style == .hold ? holdSize : persistentSize
    let screenH = screen.frame.height
    let icons = apps.map { app -> (DockApp, CGRect) in
      let ax = app.frame
      let cocoa = CGRect(x: ax.minX, y: screenH - ax.maxY, width: ax.width, height: ax.height)
      return (app, cocoa)
    }
    let side = Self.detectSide(icons: icons.map(\.1), screen: screen.frame)
    // Same numbers on the Dock copies on other displays.
    var targets = icons.map { (app: $0.0, icon: $0.1, side: side) }
    for app in apps {
      for copy in DockCopies.shared.icons(of: app.bundleURL, title: app.title) {
        targets.append((app, copy.frame, DockSide(copy.edge)))
      }
    }

    for (app, icon, side) in targets {
      let base = self.badgeOrigin(for: icon, side: side, diameter: diameter, style: style)
      let origin = base
      let panel = NSPanel(
        contentRect: CGRect(origin: origin, size: CGSize(width: diameter, height: diameter)),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.level = .screenSaver
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = style == .hold
      panel.ignoresMouseEvents = true
      panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

      panel.contentView = GlassBadgeView(diameter: diameter, text: "\(app.index % 10)", dark: dark)
      panel.alphaValue = 0
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.12
        panel.animator().alphaValue = 1
      }
      panels.append(panel)
    }
    styleShown = style
  }

  @MainActor
  func hide() {
    for p in panels { p.orderOut(nil) }
    panels.removeAll()
    styleShown = nil
  }

  private func badgeOrigin(for icon: CGRect, side: DockSide, diameter: CGFloat, style: BadgeStyle) -> CGPoint {
    switch style {
    case .persistent:
      // A corner of the icon, inset so the badge sits fully on the icon,
      // inside the Dock perimeter: lower-right with the Dock on the left,
      // top-left otherwise.
      if side == .left {
        // The Dock's item frames are wider than the icon: use the square
        // in their middle so the badge lands on the icon's corner.
        let s = min(icon.width, icon.height)
        let square = CGRect(x: icon.midX - s / 2, y: icon.midY - s / 2, width: s, height: s)
        // Overhang the icon's right edge slightly, like the Dock's own badges.
        return CGPoint(x: square.maxX - diameter + 2, y: square.minY + cornerInset)
      }
      return CGPoint(x: icon.minX + cornerInset, y: icon.maxY - diameter - cornerInset)
    case .hold:
      switch side {
      case .right: // Dock on right -> badges to the left, vertically centered
        return CGPoint(x: icon.minX - gap - diameter, y: icon.midY - diameter / 2)
      case .left: // Dock on left -> badges to the right
        return CGPoint(x: icon.maxX + gap, y: icon.midY - diameter / 2)
      case .bottom: // Dock on bottom -> badges above
        return CGPoint(x: icon.midX - diameter / 2, y: icon.maxY + gap)
      case .top:
        return CGPoint(x: icon.midX - diameter / 2, y: icon.minY - gap - diameter)
      }
    }
  }

  /// Geometry-based: no Dock prefs needed, follows the icons wherever they are.
  static func detectSide(icons: [CGRect], screen: CGRect) -> DockSide {
    guard !icons.isEmpty else { return .right }
    let box = icons.reduce(icons[0]) { $0.union($1) }
    if box.width >= box.height {
      return box.midY < screen.midY ? .bottom : .top
    }
    return box.midX < screen.midX ? .left : .right
  }
}
