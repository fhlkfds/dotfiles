import QtQuick
import Quickshell

// Caelestia-style dynamic drawer.
//
// Sizing flows strictly one way: tokens -> page implicitWidth/Height -> drawer
// size -> nav width. No page reads the drawer's dimensions, which is what keeps
// this loop-free (the previous layout did the opposite and was fixed-size).
PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  visible: DashboardState.panelVisible
        && DashboardState.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  // --- active page -----------------------------------------------------------

  readonly property Item activePage: {
    switch (DashboardState.activeTab) {
    case "media": return mediaPage
    case "perf": return perfPage
    case "workspaces": return workspacesPage
    default: return dashPage
    }
  }

  // --- dynamic size ----------------------------------------------------------

  // Never larger than the screen it opens on, so it cannot go off-screen.
  readonly property int maxW: (panel.screen ? panel.screen.width : 1920) - Theme.gapXL
  readonly property int maxH: (panel.screen ? panel.screen.height : 1080)
                              - Theme.barHeight - Theme.gapXL

  readonly property int targetW:
    Math.min(maxW, activePage.implicitWidth + Theme.drawerPadding * 2)
  readonly property int targetH:
    Math.min(maxH, nav.implicitHeight + Theme.gapM
                   + activePage.implicitHeight + Theme.drawerPadding * 2)

  // Animated through driver properties and rounded: binding Behaviour straight
  // onto implicitWidth resizes the Wayland surface on sub-pixel boundaries every
  // frame, which shows up as shimmer.
  // These must stay *declarative* bindings and must never be assigned to:
  // an imperative assignment destroys the binding and they stop tracking the
  // target entirely (which silently broke resizing once already). They cannot be
  // readonly either, because Behavior needs to write them. The Behaviours are
  // gated on `visible`, so the drawer snaps to size while hidden and animates
  // only while on screen.
  property real animW: targetW
  property real animH: targetH
  Behavior on animW {
    enabled: panel.visible
    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuint }
  }
  Behavior on animH {
    enabled: panel.visible
    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuint }
  }

  // The *window* is always big enough for both the current and the incoming
  // size, so when growing it reaches its final size in one step and the surface
  // is not resized on every frame of the animation. The visible drawer below is
  // what animates. Without this the new page was laid out at full size while the
  // window was still growing, so its content was visibly clipped mid-transition.
  implicitWidth: Math.round(Math.max(animW, targetW))
  implicitHeight: Math.round(Math.max(animH, targetH))

  // The drawer itself. Centred horizontally so it grows symmetrically about the
  // Arch icon, matching anchor.gravity: Bottom -- the extra window area during a
  // transition is transparent.
  Rectangle {
    width: Math.round(panel.animW)
    height: Math.round(panel.animH)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    color: Theme.bg
    radius: Theme.radiusXL
    clip: true

    Item {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: DashboardState.panelVisible = false

      TabBar {
        id: nav
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.drawerPadding
        anchors.rightMargin: Theme.drawerPadding
        anchors.topMargin: Theme.gapS
        height: implicitHeight
      }

      // Page viewport. Clips, and scrolls when the drawer had to be clamped to
      // the screen -- so a clamp never silently hides content.
      Flickable {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: nav.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.drawerPadding
        anchors.rightMargin: Theme.drawerPadding
        anchors.bottomMargin: Theme.drawerPadding
        anchors.topMargin: Theme.gapM
        clip: true

        contentWidth: panel.activePage ? panel.activePage.implicitWidth : width
        contentHeight: panel.activePage ? panel.activePage.implicitHeight : height
        interactive: contentWidth > width || contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        // All four stay instantiated so switching tabs preserves their state;
        // only the active one is visible. Each is positioned at its intrinsic
        // size rather than filling the viewport.
        DashTab       { id: dashPage;       visible: DashboardState.activeTab === "dash" }
        MediaTab      { id: mediaPage;      visible: DashboardState.activeTab === "media" }
        PerfTab       { id: perfPage;       visible: DashboardState.activeTab === "perf" }
        WorkspacesTab { id: workspacesPage; visible: DashboardState.activeTab === "workspaces" }
      }
    }
  }

  onVisibleChanged: {
    if (visible)
      focusScope.forceActiveFocus()
  }

  onClosed: DashboardState.panelVisible = false
}
