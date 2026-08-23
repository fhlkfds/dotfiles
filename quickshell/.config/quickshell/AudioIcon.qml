import QtQuick

Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  required property string screenName

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Text {
    id: label
    anchors.centerIn: parent
    text: AudioState.glyph
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: AudioState.muted ? Theme.textMuted : Theme.text
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton)
        AudioState.toggleMute()
      else
        AudioState.togglePanel(root.screenName)
    }
    onWheel: wheel => {
      AudioState.stepVolume(wheel.angleDelta.y > 0 ? 0.03 : -0.03)
    }
  }

  AudioPanel {
    anchorItem: root
    ownerScreen: root.screenName
  }
}
