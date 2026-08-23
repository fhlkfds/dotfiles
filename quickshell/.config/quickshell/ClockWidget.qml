import QtQuick
import Quickshell

Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  implicitWidth: label.implicitWidth + root.s(24)
  implicitHeight: label.implicitHeight + root.s(6)

  Text {
    id: label
    anchors.centerIn: parent
    text: ClockState.displayText
    color: Theme.text
    font.family: Theme.uiFamily
    font.pixelSize: root.s(14)
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
      if (mouse.button === Qt.LeftButton) {
        timezonePopup.visible = false
        calendarPopup.visible = !calendarPopup.visible
      } else if (mouse.button === Qt.RightButton) {
        ClockState.cycleFormat()
      } else if (mouse.button === Qt.MiddleButton) {
        calendarPopup.visible = false
        timezonePopup.visible = !timezonePopup.visible
      }
    }
  }

  CalendarPopup {
    id: calendarPopup
    anchorItem: root
  }

  TimezonePopup {
    id: timezonePopup
    anchorItem: root
  }
}
