import QtQuick
import Quickshell

Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  required property string screenName
  function s(n) { return Theme.fs(n * root.barScale) }
  implicitWidth: clockArea.width + (statusTray.visible ? statusTray.width + root.s(6) : 0)
  implicitHeight: Math.max(clockArea.height, statusTray.height)

  Timer {
    id: closeTimer
    interval: 250
  }

  Row {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.s(6)

    Row {
      id: statusTray
      visible: clockMouse.containsMouse || trayHover.hovered || closeTimer.running
      spacing: root.s(2)

      HoverHandler {
        id: trayHover
        onHoveredChanged: {
          if (hovered)
            closeTimer.stop()
          else if (!clockMouse.containsMouse)
            closeTimer.restart()
        }
      }

      DisplayIcon { screenName: root.screenName; barScale: root.barScale }
      NetworkIcon { screenName: root.screenName; barScale: root.barScale }
      BluetoothIcon { screenName: root.screenName; barScale: root.barScale }
      AudioIcon { screenName: root.screenName; barScale: root.barScale }
      ClipboardIcon { screenName: root.screenName; barScale: root.barScale }
    }

    Item {
      id: clockArea
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
        id: clockMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onEntered: closeTimer.stop()
        onExited: {
          if (!trayHover.hovered)
            closeTimer.restart()
        }
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
