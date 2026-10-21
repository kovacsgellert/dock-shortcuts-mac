import Cocoa

/// Show/hide the menu-bar status item. Backed by config.yml via AppConfig.
/// The status item is created/destroyed in DockUtils.runChrome.
enum ShowMenuBarIcon {
  static var isEnabled: Bool {
    get { AppConfig.shared.showMenuBarIcon }
    set {
      AppConfig.shared.showMenuBarIcon = newValue
      AppConfig.shared.save()
    }
  }

  static func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
  }
}