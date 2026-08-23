import QtQuick

// Bar item for the Display panel.
//
// `screenName` is the Hyprland connector name of the monitor this bar instance
// lives on, passed down from Bar.qml. It is what makes scrolling here adjust
// *this* monitor, and what stops the popup from opening on every screen at once.
Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  required property string screenName

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  readonly property var mon: DisplayState.monitorFor(root.screenName)
  readonly property bool usable: mon !== null && mon.ddcOk

  Text {
    id: label
    anchors.centerIn: parent
    text: DisplayState.glyph
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: root.usable ? Theme.text : Theme.textMuted
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton

    onClicked: DisplayState.togglePanel(root.screenName)

    onWheel: wheel => {
      DisplayState.stepBrightness(root.screenName,
                                  wheel.angleDelta.y > 0 ? 5 : -5)
    }
  }

  DisplayPanel {
    anchorItem: root
    ownerScreen: root.screenName
  }
}
