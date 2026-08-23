import QtQuick

// Caelestia-style navigation: icon over label, with an animated underline on the
// active tab. Each enabled tab takes an equal share of the width, so disabling
// one redistributes the rest instead of leaving a gap.
Item {
  id: root

  readonly property var tabs: DashboardState.enabledTabs
  readonly property int count: Math.max(1, tabs.length)
  readonly property real tabWidth: width / count

  implicitHeight: Theme.navHeight

  Row {
    id: row
    anchors.fill: parent

    Repeater {
      model: root.tabs

      Item {
        required property var modelData
        required property int index
        readonly property bool isActive: DashboardState.activeTab === modelData.key
        width: root.tabWidth
        height: root.height

        Column {
          anchors.centerIn: parent
          spacing: Theme.gapXS - 1

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.icon
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.navIcon
            color: parent.parent.isActive ? Theme.accent : Theme.textDim
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.label
            font.pixelSize: Theme.navLabel
            font.bold: parent.parent.isActive
            color: parent.parent.isActive ? Theme.accent : Theme.textDim
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: DashboardState.activeTab = modelData.key
        }
      }
    }
  }

  // Active indicator. Animated in x and width so it slides between tabs.
  Rectangle {
    id: indicator
    height: Theme.tabIndicator
    radius: height / 2
    color: Theme.accent
    y: root.height - height

    readonly property int activeIndex: {
      for (var i = 0; i < root.tabs.length; i++)
        if (root.tabs[i].key === DashboardState.activeTab)
          return i
      return 0
    }

    width: root.tabWidth * 0.5
    x: root.tabWidth * indicator.activeIndex + (root.tabWidth - width) / 2

    Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
  }

  // Wheel over the strip steps between tabs.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: wheel => DashboardState.stepTab(wheel.angleDelta.y > 0 ? -1 : 1)
  }
}
