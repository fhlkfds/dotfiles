import QtQuick

// Clock-tray status control for native Quickshell Do Not Disturb,
// content-sized like the other status icons in the tray (UpdatesIcon,
// DisplayIcon) and accent-filled while DND is on.
Item {
  id: root

  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  // Rasterised against JetBrainsMono Nerd Font (upstream ryanoasis release,
  // cmap check): 0xf009a is md-bell and 0xf0a91 is md-bell_off_outline.
  // Note the two do not sit adjacent in the Material Design Icons range.
  readonly property string glyphBellOn: String.fromCodePoint(0xf009a)
  readonly property string glyphBellOff: NotifyState.glyphBellOff

  readonly property bool dnd: NotifyState.dnd

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: root.dnd ? Theme.accent : "transparent"
    border.width: Theme.borderWidth
    border.color: root.dnd ? Theme.accent : Theme.surface
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.dnd ? root.glyphBellOff : root.glyphBellOn
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: root.dnd ? Theme.bgDeep : Theme.text
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: NotifyState.toggle()
  }
}
