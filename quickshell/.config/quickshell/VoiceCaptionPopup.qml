import Quickshell
import Quickshell.Wayland
import QtQuick

// Bottom-centre dictation pill on the overlay layer. Every screen has one, but
// only the screen that was focused when dictation started shows it. It sits
// above the OSD pill's slot (OsdPopup: Theme.fs(96)) so the two never overlap.
// The empty mask makes it click-through.
PanelWindow {
  id: window
  required property var output
  screen: output

  visible: VoiceCaptionState.screenName === output.name && (VoiceCaptionState.visible || pill.opacity > 0)
  color: "transparent"
  anchors.bottom: true
  margins.bottom: Theme.fs(96) + Theme.fs(60) + Theme.gapM
  implicitWidth: pill.implicitWidth
  implicitHeight: pill.implicitHeight
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}

  WlrLayershell.namespace: "quickshell-voice-caption"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  VoiceCaptionPill {
    id: pill
    anchors.fill: parent
    caption: VoiceCaptionState
  }
}
