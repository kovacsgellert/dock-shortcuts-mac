import Cocoa
import ApplicationServices

/// Settings window, macOS System Settings style: icon header, grouped boxes,
/// centered About footer. Always used from the main thread.
final class SettingsWindowController: NSWindowController {
  private var loginSwitch: NSSwitch!
  private var loginErrorLabel: NSTextField!
  private var accessLabel: NSTextField!
  private var accessButton: NSButton!
  private var menubarSwitch: NSSwitch!
  private var alwaysSwitch: NSSwitch!
  private var themePopup: NSPopUpButton!
  private var delaySlider: NSSlider!
  private var delayLabel: NSTextField!
  private var accessPoll: Timer?

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "DockShortcuts"
    window.center()
    window.isReleasedWhenClosed = false
    super.init(window: window)
    buildUI()
    fitToContent()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError() }

  static let shared = SettingsWindowController()

  // MARK: - Layout

  private func buildUI() {
    guard let content = window?.contentView else { return }
    let stack = NSStackView()
    stack.identifier = NSUserInterfaceItemIdentifier("root")
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
    ])

    // Header: app icon + name + hint.
    let header = NSStackView()
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 12
    let iconView = NSImageView(image: NSApp.applicationIconImage)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 56),
      iconView.heightAnchor.constraint(equalToConstant: 56),
    ])
    header.addArrangedSubview(iconView)
    let titleStack = NSStackView()
    titleStack.orientation = .vertical
    titleStack.alignment = .leading
    titleStack.spacing = 2
    let nameRow = NSStackView()
    nameRow.orientation = .horizontal
    nameRow.alignment = .lastBaseline
    nameRow.spacing = 8
    let title = NSTextField(labelWithString: "DockShortcuts")
    title.font = .systemFont(ofSize: 16, weight: .semibold)
    nameRow.addArrangedSubview(title)
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
      let versionLabel = NSTextField(labelWithString: version)
      versionLabel.font = .systemFont(ofSize: 12)
      versionLabel.textColor = .secondaryLabelColor
      nameRow.addArrangedSubview(versionLabel)
    }
    titleStack.addArrangedSubview(nameRow)
    let hint = NSTextField(wrappingLabelWithString: "Hold Option for numbers, press 1–9 or 0 to switch apps. Press again to cycle an app's windows.")
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .secondaryLabelColor
    // Bound the unwrapped intrinsic width (400 window − 40 insets − 56 icon − 12 gap),
    // otherwise the stack overflows and AppKit breaks the leading constraint.
    hint.preferredMaxLayoutWidth = 292
    titleStack.addArrangedSubview(hint)
    header.addArrangedSubview(titleStack)
    stack.addArrangedSubview(header)

    // General group.
    loginSwitch = NSSwitch()
    loginSwitch.target = self
    loginSwitch.action = #selector(loginToggled(_:))
    let menubarSwitchLocal = NSSwitch()
    menubarSwitchLocal.target = self
    menubarSwitchLocal.action = #selector(menubarToggled(_:))
    menubarSwitch = menubarSwitchLocal
    let alwaysSwitchLocal = NSSwitch()
    alwaysSwitchLocal.target = self
    alwaysSwitchLocal.action = #selector(alwaysToggled(_:))
    alwaysSwitch = alwaysSwitchLocal
    let themePopup = NSPopUpButton()
    themePopup.addItems(withTitles: AppAppearance.allCases.map(\.label))
    themePopup.target = self
    themePopup.action = #selector(appearanceChanged(_:))
    self.themePopup = themePopup

    let delayRow = NSStackView()
    delayRow.orientation = .horizontal
    delayRow.alignment = .centerY
    delayRow.spacing = 8
    // Same row height as the switch/popup rows so the rhythm stays even.
    delayRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    delaySlider = NSSlider(value: 100, minValue: 0, maxValue: 500, target: self, action: #selector(delayChanged(_:)))
    delaySlider.translatesAutoresizingMaskIntoConstraints = false
    delaySlider.widthAnchor.constraint(equalToConstant: 130).isActive = true
    delayRow.addArrangedSubview(delaySlider)
    delayLabel = NSTextField(labelWithString: "")
    delayLabel.font = .systemFont(ofSize: 13)
    delayLabel.alignment = .right
    delayLabel.translatesAutoresizingMaskIntoConstraints = false
    delayLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
    delayRow.addArrangedSubview(delayLabel)
    stack.addArrangedSubview(section(title: "General", rows: [
      ("Start automatically when you log in", loginSwitch),
      ("Show menu bar icon", menubarSwitchLocal),
      ("Badges always visible", alwaysSwitchLocal),
      ("Badge delay", delayRow),
      ("Appearance", themePopup),
    ]))
    loginErrorLabel = NSTextField(wrappingLabelWithString: "")
    loginErrorLabel.font = .systemFont(ofSize: 12)
    loginErrorLabel.textColor = .systemRed
    loginErrorLabel.preferredMaxLayoutWidth = 360
    loginErrorLabel.isHidden = true
    stack.addArrangedSubview(loginErrorLabel)

    // Accessibility group.
    accessLabel = NSTextField(wrappingLabelWithString: "")
    accessLabel.font = .systemFont(ofSize: 13)
    accessLabel.preferredMaxLayoutWidth = 332
    accessButton = NSButton(title: "Open System Settings…", target: self, action: #selector(openAccessibilitySettings(_:)))
    accessButton.bezelStyle = .rounded
    stack.addArrangedSubview(section(title: "Accessibility", rows: [(nil, accessLabel), (nil, accessButton)]))

    // About section, laid out like the others: leading-aligned under
    // its caption instead of centered.
    let footer = NSStackView()
    footer.orientation = .vertical
    footer.alignment = .leading
    footer.spacing = 4
    footer.translatesAutoresizingMaskIntoConstraints = false
    let aboutCaption = NSTextField(labelWithString: "About")
    aboutCaption.font = .systemFont(ofSize: 13, weight: .semibold)
    aboutCaption.textColor = .secondaryLabelColor
    footer.addArrangedSubview(aboutCaption)
    aboutCaption.font = .systemFont(ofSize: 13, weight: .semibold)
    aboutCaption.textColor = .secondaryLabelColor
    aboutCaption.alignment = .center
    footer.addArrangedSubview(aboutCaption)
    let aboutName = NSTextField(labelWithString: "Made by Gellért Kovács")
    aboutName.font = .systemFont(ofSize: 12)
    aboutName.textColor = .secondaryLabelColor
    footer.addArrangedSubview(aboutName)
    let repoURL = URL(string: "https://github.com/kovacsgellert/dock-shortcuts-mac")!
    let repoLink = NSTextField(wrappingLabelWithString: "")
    repoLink.isEditable = false
    repoLink.isSelectable = true
    repoLink.preferredMaxLayoutWidth = 360
    repoLink.attributedStringValue = NSAttributedString(
      string: "github.com/kovacsgellert/dock-shortcuts-mac",
      attributes: [.link: repoURL, .font: NSFont.systemFont(ofSize: 12)]
    )
    // Selectable fields don't always fire links on single click — belt and braces.
    repoLink.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openRepo(_:))))
    footer.addArrangedSubview(repoLink)
    stack.addArrangedSubview(footer)

    refreshAll()
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshAccessibility),
      name: NSApplication.didBecomeActiveNotification, object: nil
    )
  }

  /// Caption + rounded group with label/control rows (nil label = full-width row).
  private func section(title: String, rows: [(String?, NSView)]) -> NSView {    let wrap = NSStackView()
    wrap.orientation = .vertical
    wrap.alignment = .leading
    wrap.spacing = 6
    wrap.translatesAutoresizingMaskIntoConstraints = false
    let caption = NSTextField(labelWithString: title)
    caption.font = .systemFont(ofSize: 13, weight: .semibold)
    caption.textColor = .secondaryLabelColor
    wrap.addArrangedSubview(caption)

    let boxView = GroupBoxView()
    boxView.translatesAutoresizingMaskIntoConstraints = false
    let inner = NSStackView()
    inner.orientation = .vertical
    inner.spacing = 12
    inner.translatesAutoresizingMaskIntoConstraints = false
    for (label, control) in rows {
      if let label {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 13)
        l.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.addArrangedSubview(l)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        inner.addArrangedSubview(row)
      } else {
        inner.addArrangedSubview(control)
      }
    }
    boxView.addSubview(inner)
    NSLayoutConstraint.activate([
      inner.topAnchor.constraint(equalTo: boxView.topAnchor, constant: 12),
      inner.leadingAnchor.constraint(equalTo: boxView.leadingAnchor, constant: 14),
      inner.trailingAnchor.constraint(equalTo: boxView.trailingAnchor, constant: -14),
      inner.bottomAnchor.constraint(equalTo: boxView.bottomAnchor, constant: -12),
    ])
    wrap.addArrangedSubview(boxView)
    return wrap
  }

  /// Shrink the window to its content so nothing clips.
  private func fitToContent() {
    guard let window, let content = window.contentView else { return }
    content.layoutSubtreeIfNeeded()
    // Measure the root stack itself: contentView.fittingSize overshoots.
    let root = content.subviews.first { $0.identifier?.rawValue == "root" }
    let fitting = root?.fittingSize.height ?? content.fittingSize.height
    if fitting > 0, fitting < 800 {
      window.setContentSize(NSSize(width: 400, height: fitting))
      window.center()
    }
  }

  // MARK: - Behavior

  func show() {
    refreshAll()
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate()
    // Live-update the permission row while open: the grant happens in
    // System Settings, so a one-time check would go stale.
    accessPoll?.invalidate()
    accessPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self, window?.isVisible == true else { return }
      refreshAccessibility()
    }
  }

  @objc func showFromMenu(_: Any?) {
    show()
  }

  private func refreshAll() {
    // Re-read config.yml: hand/script edits show up on next open.
    AppConfig.shared.reload()
    // Dev builds can't own the login item (see loginToggled): show the
    // switch disabled rather than a meaningless state.
    loginSwitch.isEnabled = DockNumbers.isAppBundle
    loginSwitch.toolTip = DockNumbers.isAppBundle ? nil : "Start-at-login is managed by the installed DockShortcuts.app, not dev builds."
    loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
    menubarSwitch.state = ShowMenuBarIcon.isEnabled ? .on : .off
    alwaysSwitch.state = AppConfig.shared.badgesAlwaysVisible ? .on : .off
    themePopup.selectItem(withTitle: AppAppearance.current.label)
    delaySlider.doubleValue = Double(AppConfig.shared.badgeDelayMs)
    delayLabel.stringValue = "\(AppConfig.shared.badgeDelayMs) ms"
    updateDelayEnabled()
    loginErrorLabel.isHidden = true
    refreshAccessibility()
  }

  @objc private func loginToggled(_ sender: NSSwitch) {
    // Dev builds run as a bare binary: toggling here would register that
    // throwaway binary (or unregister the installed app) at login.
    guard DockNumbers.isAppBundle else {
      sender.state = .off
      loginErrorLabel.stringValue = "Start-at-login is managed by the installed DockShortcuts.app, not dev builds."
      loginErrorLabel.isHidden = false
      return
    }
    loginErrorLabel.isHidden = true
    do {
      try LaunchAtLogin.setEnabled(sender.state == .on)
      AppConfig.shared.startAtLogin = sender.state == .on
      AppConfig.shared.save()
    } catch {
      loginErrorLabel.stringValue = "Couldn't change login item: \(error.localizedDescription)"
      loginErrorLabel.isHidden = false
      sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }
  }

  @objc private func menubarToggled(_ sender: NSSwitch) {
    ShowMenuBarIcon.setEnabled(sender.state == .on)
    DockNumbers.updateStatusItem(settings: SettingsWindowController.shared)
  }

  @objc private func refreshAccessibility() {
    let granted = AXIsProcessTrusted()
    accessLabel.stringValue = granted
      ? "Accessibility access: granted ✓"
      : "Accessibility access: required to badge the Dock"
    // No need to offer System Settings when there's nothing to fix.
    accessButton.isHidden = granted
  }

  @objc private func openAccessibilitySettings(_: NSButton) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }

  @objc private func openRepo(_: NSGestureRecognizer) {
    NSWorkspace.shared.open(URL(string: "https://github.com/kovacsgellert/dock-shortcuts-mac")!)
  }

  @objc private func appearanceChanged(_ sender: NSPopUpButton) {
    guard let selected = AppAppearance.allCases.first(where: { $0.label == sender.titleOfSelectedItem }) else { return }
    AppAppearance.current = selected
    AppAppearance.apply()
  }

  @objc private func alwaysToggled(_ sender: NSSwitch) {
    AppConfig.shared.badgesAlwaysVisible = sender.state == .on
    AppConfig.shared.save()
    updateDelayEnabled()
    NotificationCenter.default.post(name: .appConfigChanged, object: nil)
  }

  /// The hold-to-show delay is meaningless with persistent minis on screen.
  private func updateDelayEnabled() {
    let enabled = !AppConfig.shared.badgesAlwaysVisible
    delaySlider.isEnabled = enabled
    delayLabel.textColor = enabled ? .labelColor : .disabledControlTextColor
  }

  @objc private func delayChanged(_ sender: NSSlider) {
    let ms = min(max(Int(sender.doubleValue.rounded()), 0), 500)
    AppConfig.shared.badgeDelayMs = ms
    AppConfig.shared.save()
    delayLabel.stringValue = "\(ms) ms"
  }
}

/// Rounded settings group whose fill tracks light/dark appearance.
/// (Resolving a dynamic NSColor to CGColor once would freeze the
/// creation-time appearance — this re-resolves on every change.)
private final class GroupBoxView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 10
    refresh()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError() }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  private func refresh() {
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
  }
}
