import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "DesktopCover.js" as DesktopCover

// Spotify now-playing card above the wallpaper and below application windows,
// one per output, in the bottom-left corner opposite the desktop clock.
//
// Unlike DesktopClock this window is sized to the card rather than the whole
// screen, so the buttons take clicks while the rest of the desktop stays
// untouched, and the record's animation repaints a small surface.
PanelWindow {
  id: panel
  required property var output
  screen: output

  // Stop the record spinning while windows hide the card, so it does not keep
  // the output redrawing.
  readonly property bool covered: DesktopCover.covered(Hyprland.monitorFor(output))

  visible: SpotifyState.hasTrack
  anchors { bottom: true; left: true }
  // Lifts above the desktop clock when the output is too narrow to share the
  // bottom edge with it.
  margins { bottom: card.bottomMargin(output.width); left: card.edgeMargin }
  implicitWidth: card.implicitWidth + Theme.fs(8)
  implicitHeight: card.implicitHeight + Theme.fs(8)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "quickshell-desktop-now-playing"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  DesktopNowPlayingCard {
    id: card
    anchors.centerIn: parent
    spinAllowed: !panel.covered
  }
}
