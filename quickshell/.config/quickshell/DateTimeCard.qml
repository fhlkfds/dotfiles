import QtQuick

// Vertical date/time card. Reads ClockState so it follows the format and
// timezone configured for the bar clock rather than keeping a second clock.
Card {
  id: root
  implicitWidth: Theme.dateCardW
  implicitHeight: Theme.dateCardH
  radius: Theme.radiusXL
  padding: Theme.gapM

  readonly property var now: ClockState.zonedDate()
  // Respect the 12/24-hour choice already made in ClockState's format list.
  readonly property bool ampm: ClockState.formats[ClockState.formatIndex].indexOf("AP") !== -1

  Column {
    anchors.centerIn: parent
    spacing: Theme.gapXS

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, "ddd").toUpperCase()
      color: Theme.textDim
      font.pixelSize: Theme.fs(13)
      font.bold: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, "d")
      color: Theme.text
      font.bold: true
      font.pixelSize: Theme.fs(44)
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, "MMM").toUpperCase()
      color: Theme.textDim
      font.pixelSize: Theme.fs(14)
    }
    Item { width: 1; height: Theme.gapS }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, root.ampm ? "h:mm" : "HH:mm")
      color: Theme.accent
      font.bold: true
      font.pixelSize: Theme.fs(24)
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.ampm
      text: Qt.formatDateTime(root.now, "AP")
      color: Theme.textMuted
      font.pixelSize: Theme.fs(12)
    }
  }
}
