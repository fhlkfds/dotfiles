import QtQuick

// Far-left bar item: opens the dashboard dropdown.
// Glyph is dev-archlinux (U+E732), verified against the installed
// JetBrainsMono Nerd Font cmap and post table.
Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  required property string screenName

  implicitWidth: label.implicitWidth + root.s(14)
  implicitHeight: label.implicitHeight + root.s(6)

  readonly property bool active: DashboardState.panelVisible
                              && DashboardState.panelScreen === root.screenName

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: root.active ? Theme.accent : "transparent"
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: String.fromCodePoint(0xe732) // dev-archlinux
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: root.active ? Theme.bgDeep : Theme.text
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: DashboardState.togglePanel(root.screenName)
  }

}
