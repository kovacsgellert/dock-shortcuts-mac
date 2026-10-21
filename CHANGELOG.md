# Changelog

## 2.0.0-beta1

- Renamed to DockUtils (`dock-utils-mac`), with a new bundle id
  `com.kovacsgellert.dock-utils`: macOS sees a new app, so grant
  Accessibility again (see README → Updating). Settings are copied from
  `~/.config/dock-shortcuts/` on first launch
- Dock copies on other displays (Settings → Other Displays, off by
  default): the Dock's items, running indicators and badges on every
  display the real Dock isn't on, matching its position, icon size and
  auto-hide. Zoomed and tiled windows stop at the copy's edge

## 1.3.0

- No changes since 1.3.0-beta1

## 1.3.0-beta1

- Settings: Quit DockShortcuts button, so the app can be closed even with
  the menu bar icon hidden
- Releases are signed with a stable self-signed certificate, so macOS keeps
  the Accessibility permission across updates. Updating to this release from
  1.2.0 or older still needs one re-grant (see README → Updating)
- README: first-launch steps for macOS 15+ (Open Anyway)

## 1.2.0

- No changes since 1.2.0-beta1

## 1.2.0-beta1

- Option+number only triggers with Option alone: combos that add Cmd, Ctrl
  or Shift (e.g. Option+Cmd+Ctrl+4) pass through to other apps, and badges
  hide while those modifiers are held

## 1.1.0

- Repeat-pressing an app's number cycles through its windows when it has
  several open (instead of hiding it)
- Dev builds no longer touch the start-at-login item; the toggle is
  disabled there

## 1.0.0

- Rename to DockShortcuts (`dock-shortcuts-mac`): new bundle id
  `com.kovacsgellert.dock-shortcuts`, settings migrate automatically
  from the old config location

## 0.2.0

- Always-visible: holding Option no longer pops badges out (no visible change)
- Disable badge-delay slider when always-visible is on

## 0.2.0-beta1

- Always-visible Dock badges with live Dock tracking
- Settings: always-visible toggle, Appearance moved last

## 0.1.4

- Restore minimized Finder windows on switch

## 0.1.3

- Show app icon at top of README
- Versioned installer filenames

## 0.1.2

- Fix settings group boxes staying dark in light mode

## 0.1.1

- Fix `.pkg` to always install into `/Applications`

## 0.1.0

- Add app icon + menu-bar template (code-rendered)
- Wire custom icon into the `.app` bundle and menu bar
- Show settings window on reopen (Spotlight/click while running)
- Add show/hide menu-bar icon setting
- Retain status item, apply menu-bar visibility live
- Lay settings out as a grid: labels left, controls right
- Add About section in settings: author + repo link
- Restyle settings macOS-style: icon header, grouped sections
- Portable `~/.config` YAML settings store + configurable badge delay
- Settings: delay slider, disk-backed refresh, layout overflow fixes
- Add `--no-accessibility` flag for headless UI testing
- Group name + repo link under an About section
- Fix settings launch crash, footer centering, row rhythm
- Unify settings alignment: About leading, even row heights
- Show app name (+ version) as menu-bar menu header
- Menu-bar icon: mini dock with badge dots instead of 1-disc
- Match app icon to menu-bar motif; show version in settings
- Honor `XDG_CONFIG_HOME` for the config file location
- Add dock overlay screenshot to README
- Ship the app: `.app` bundle, DMG installer, settings, themes
- Open a new Finder window when switching to Finder with none open
- Add `.pkg` installer that puts the app into `/Applications`
- Hold Option to badge Dock icons, press number to switch apps
- Move sources to `src/`, add README, MIT license, AI disclosure
- Tag-triggered release workflow with install docs
