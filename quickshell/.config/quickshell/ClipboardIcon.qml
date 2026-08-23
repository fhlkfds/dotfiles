import QtQuick

// Bar item beside the clock; opens the clipboard history popup.
// Same popup the Super+Ctrl+V keybind toggles -- one shared singleton, no
// duplicated state or UI.
Item {
  id: root
  required property string screenName

  // Bar chrome scale, passed down from Bar.qml.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  readonly property bool active: ClipboardState.panelVisible
                              && ClipboardState.panelScreen === root.screenName

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: root.active ? Theme.accent : "transparent"
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: ClipboardState.glyphClipboard
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: root.active ? Theme.bgDeep : Theme.text
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: ClipboardState.togglePanel(root.screenName)
  }

  ClipboardPanel {
    anchorItem: root
    ownerScreen: root.screenName
  }
}
