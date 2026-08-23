pragma Singleton
import Quickshell
import QtQuick

// Open/closed state and tab selection for the Arch dashboard dropdown.
// Follows the same per-screen popup convention as MediaState / DisplayState /
// NetworkState / AudioState.
Singleton {
  id: root

  property bool panelVisible: false
  // Connector name of the screen whose bar opened the panel, so the popup shows
  // on the monitor that was clicked rather than on all of them.
  property string panelScreen: ""

  // "dash" | "media" | "perf" | "weather". Kept across open/close so reopening
  // returns to the tab you were last on.
  property string activeTab: "dash"

  // Never leave a disabled tab selected.
  onEnabledTabsChanged: {
    for (var i = 0; i < enabledTabs.length; i++)
      if (enabledTabs[i].key === activeTab)
        return
    if (enabledTabs.length > 0)
      activeTab = enabledTabs[0].key
  }

  // `enabled` lets a section be hidden; the nav redistributes the remaining tabs
  // evenly rather than leaving a gap. Glyph codepoints verified against the
  // installed JetBrainsMono Nerd Font cmap and post table.
  // These codepoints are above U+FFFF, so they must be built with
  // String.fromCodePoint -- a "\uXXXX" escape only takes four hex digits and
  // would silently render the wrong glyph plus a stray character.
  property var tabs: [
    { key: "dash",    label: "Dashboard",   icon: String.fromCodePoint(0xf056e), enabled: true },
    { key: "media",   label: "Media",       icon: String.fromCodePoint(0xf075a), enabled: true },
    { key: "perf",    label: "Performance", icon: String.fromCodePoint(0xf04c5), enabled: true },
    { key: "weather", label: "Weather",     icon: String.fromCodePoint(0xf0595), enabled: true }
  ]

  readonly property var enabledTabs: tabs.filter(t => t.enabled)

  function stepTab(delta) {
    const list = root.enabledTabs
    if (list.length === 0)
      return
    var i = 0
    for (var k = 0; k < list.length; k++)
      if (list[k].key === root.activeTab)
        i = k
    // Clamped rather than wrapping, so a fast scroll settles at an end instead
    // of cycling indefinitely.
    const next = Math.max(0, Math.min(list.length - 1, i + delta))
    root.activeTab = list[next].key
  }

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
  }
}
