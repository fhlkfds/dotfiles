pragma Singleton
import Quickshell
import QtQuick

// Open/closed state and tab for the clock dashboard. Same per-screen popup
// convention as MediaState / NetworkState / AudioState: the bar instance whose
// clock was clicked is the one that shows the panel.
Singleton {
  id: root

  property bool panelVisible: false
  property string panelScreen: ""

  // "overview" | "media" | "system" | "weather"
  property string activeTab: "overview"
  readonly property var tabs: ["overview", "media", "system", "weather"]

  // Clicking the clock always lands on the overview; the tab you wander off to
  // is not remembered across opens.
  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    activeTab = "overview"
    panelScreen = screenName
    panelVisible = true
  }

  function stepTab(delta) {
    const i = tabs.indexOf(activeTab)
    activeTab = tabs[Math.max(0, Math.min(tabs.length - 1, i + delta))]
  }
}
