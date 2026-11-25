import QtQuick
import "timer/TimerLogic.js" as TimerLogic

// Bar pill for the countdown timer, left of the clock. Accent while running,
// a pulsing critical "Done" once it rings. Hidden when no timer is set.
Item {
  id: root
  required property string screenName
  property real barScale: 1.0
  property var timerState: TimerState
  function s(n) { return Theme.fs(n * root.barScale) }

  readonly property string phase: timerState.current.phase
  readonly property bool finished: phase === "done"
  readonly property string label: finished ? "Done"
    : (phase === "running" ? TimerLogic.formatRemaining(timerState.remainingMs) : "")
  property real pulse: 1

  visible: phase !== "idle"
  implicitWidth: pill.width
  implicitHeight: pill.height

  SequentialAnimation on pulse {
    running: root.finished && root.visible
    loops: Animation.Infinite
    NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
  }

  Rectangle {
    id: pill
    width: content.implicitWidth + root.s(14)
    height: content.implicitHeight + root.s(6)
    radius: Theme.radiusCell
    color: root.finished ? Theme.critical : Theme.accent
    opacity: root.finished ? root.pulse : 1

    Row {
      id: content
      anchors.centerIn: parent
      spacing: root.s(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: String.fromCodePoint(0xf051b) // md-timer_outline
        color: Theme.onAccent
        font.family: Theme.glyphFamily
        font.pixelSize: root.s(15)
      }

      // The glyph font is monospaced, so the digits keep one width and the
      // pill does not jitter as the seconds change.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.onAccent
        font.family: Theme.glyphFamily
        font.bold: true
        font.pixelSize: root.s(12)
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: root.finished ? root.timerState.dismiss()
                             : root.timerState.togglePanel(root.screenName)
  }
}
