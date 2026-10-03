import QtQuick
import Quickshell

// The clock dashboard: overview, media, system and weather tabs, dropped
// under the bar clock. Opened by clicking the clock or the weather beside it,
// or `quickshell ipc call dashboard toggle`.
//
// Built for speed. Every page is created once with the bar and stays alive,
// so opening only maps the window and switching tabs only flips `visible`.
// The window is one fixed size for every tab, so a tab switch never resizes
// the Wayland surface, and nothing animates on open, close or switch.
PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  visible: DashboardState.panelVisible && DashboardState.panelScreen === panel.ownerScreen
  grabFocus: true
  color: "transparent"

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: Theme.gapS

  implicitWidth: view.implicitWidth
  // Never taller than the screen under the bar; the view scrolls instead.
  implicitHeight: Math.min(view.implicitHeight,
                           (panel.screen ? panel.screen.height : 1080) - Theme.barHeight - Theme.gapL)

  DashboardView {
    id: view
    anchors.fill: parent
    shown: panel.visible
  }

  onVisibleChanged: {
    if (visible) {
      view.forceActiveFocus()
      WeatherState.maybeRefresh()
    } else if (DashboardState.panelScreen === panel.ownerScreen) {
      // A click outside dismisses the popup without going through the state.
      DashboardState.panelVisible = false
    }
  }
}
