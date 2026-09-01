import QtQuick

Item {
  id: root

  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  visible: WindowsVmState.phase !== "off"
  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Rectangle {
    id: pill
    anchors.fill: parent
    radius: Theme.radiusCell
    color: WindowsVmState.phase === "ready" ? Theme.accent : Theme.warning

    SequentialAnimation on opacity {
      running: root.visible && WindowsVmState.phase === "starting"
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.5; duration: 700; easing.type: Easing.InOutQuad }
      NumberAnimation { from: 0.5; to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
    }
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: String.fromCodePoint(0xe70f) // dev-windows
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: Theme.onAccent
  }
}
