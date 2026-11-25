import QtQuick
import "timer/TimerLogic.js" as TimerLogic

// What TimerPanel shows. Split out so TimerSmoke and the shot harness can
// load it without a PanelWindow. It reads and acts only through timerState,
// so a test can hand it any object with the same shape.
Item {
  id: root
  property var timerState: TimerState
  signal closeRequested()

  readonly property bool running: timerState.current.phase === "running"
  readonly property var presets: timerState.presets
  readonly property var parsed: TimerLogic.parseDuration(input.text)
  readonly property bool typing: input.text.trim() !== ""
  readonly property string liveText: !typing ? ""
    : parsed.error !== undefined ? parsed.error
    : "→ " + TimerLogic.describe(parsed.ms) + " · rings at "
      + TimerLogic.clockTime(timerState.clock() + parsed.ms)
  readonly property string hintText: "Alt+" + (presets.length > 1 ? "1–" + presets.length : "1")
    + " preset · Enter start · Esc close"
  readonly property string runningLabel: timerState.current.label
    || TimerLogic.describe(timerState.current.durationMs) + " timer"
  property alias inputText: input.text

  implicitWidth: Theme.fs(340)
  implicitHeight: body.implicitHeight
  focus: true
  Keys.onEscapePressed: root.closeRequested()

  // Presets sit on Alt+digit so a bare digit always types: "10" is ten minutes.
  function pickPreset(index) {
    if (index < 0 || index >= presets.length) return false
    timerState.start(presets[index] * TimerLogic.MINUTE_MS, "")
    return true
  }

  function submit() {
    if (parsed.error !== undefined) return false
    timerState.start(parsed.ms, "")
    return true
  }

  function focusInput() {
    if (!running) input.forceActiveFocus()
    else root.forceActiveFocus()
  }

  onVisibleChanged: if (visible) { input.text = ""; focusInput() }
  onRunningChanged: if (visible) focusInput()

  component ActionButton: Rectangle {
    id: button
    property string label: ""
    property color labelColor: Theme.text
    property color fill: Theme.surface
    signal clicked()
    implicitHeight: Theme.fs(34)
    radius: Theme.radiusCell
    color: buttonMouse.containsMouse ? Theme.surfaceAlt : fill
    Text {
      anchors.centerIn: parent
      text: button.label
      color: button.labelColor
      font.bold: true
      font.pixelSize: Theme.fs(12)
    }
    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: button.clicked()
    }
  }

  Column {
    id: body
    width: root.width
    spacing: Theme.gapM

    Text {
      text: "Timer"
      color: Theme.text
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.menuFontTitle
      font.bold: true
    }

    Column {
      id: idleView
      visible: !root.running
      width: parent.width
      spacing: Theme.gapM

      Row {
        id: chips
        spacing: Theme.gapS
        Repeater {
          model: root.presets
          Rectangle {
            id: chip
            required property int index
            required property var modelData
            width: (idleView.width - (root.presets.length - 1) * chips.spacing) / root.presets.length
            height: Theme.fs(56)
            radius: Theme.radiusCell
            color: chipMouse.containsMouse ? Theme.surfaceAlt : Theme.surface
            Column {
              anchors.centerIn: parent
              spacing: Theme.fs(2)
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: TimerLogic.describe(chip.modelData * TimerLogic.MINUTE_MS)
                color: Theme.text
                font.bold: true
                font.pixelSize: Theme.fs(13)
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Alt+" + (chip.index + 1)
                color: Theme.textMuted
                font.pixelSize: Theme.fs(10)
              }
            }
            MouseArea {
              id: chipMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.pickPreset(chip.index)
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Theme.fs(36)
        radius: Theme.radiusCell
        color: Theme.surface
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : "transparent"

        TextInput {
          id: input
          anchors.fill: parent
          anchors.leftMargin: Theme.gapM
          anchors.rightMargin: Theme.gapM
          verticalAlignment: TextInput.AlignVCenter
          color: Theme.text
          font.pixelSize: Theme.fs(13)
          clip: true
          // Digits, h m s and the colon; TimerLogic.parseDuration does the rest.
          validator: RegularExpressionValidator { regularExpression: /[0-9hmsHMS: ]{0,12}/ }
          onAccepted: root.submit()
          Keys.onEscapePressed: root.closeRequested()
          Keys.onPressed: event => {
            const number = event.key - Qt.Key_1
            if (number >= 0 && number < 9
                && (event.modifiers & ~Qt.KeypadModifier) === Qt.AltModifier
                && root.pickPreset(number))
              event.accepted = true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: "or type a time: 7m30s, 1h, 90s"
            color: Theme.textMuted
            font.pixelSize: Theme.fs(13)
          }
        }
      }

      Text {
        width: parent.width
        height: Theme.fs(16)
        text: root.liveText
        elide: Text.ElideRight
        color: root.parsed.error !== undefined ? Theme.critical : Theme.textMuted
        font.pixelSize: Theme.fs(12)
      }

      Text {
        width: parent.width
        text: root.hintText
        color: Theme.textMuted
        font.pixelSize: Theme.fs(11)
      }
    }

    Column {
      id: runView
      visible: root.running
      width: parent.width
      spacing: Theme.gapM

      Text {
        width: parent.width
        text: root.runningLabel
        elide: Text.ElideRight
        color: Theme.textMuted
        font.pixelSize: Theme.fs(12)
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: TimerLogic.formatRemaining(root.timerState.remainingMs)
        color: Theme.text
        font.family: Theme.glyphFamily
        font.bold: true
        font.pixelSize: Theme.fs(44)
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "rings at " + TimerLogic.clockTime(root.timerState.current.endsAt)
        color: Theme.textMuted
        font.pixelSize: Theme.fs(12)
      }

      Rectangle {
        id: track
        width: parent.width
        height: Theme.fs(6)
        radius: height / 2
        color: Theme.surface
        Rectangle {
          width: track.width * root.timerState.progress
          height: parent.height
          radius: parent.radius
          color: Theme.accent
        }
      }

      Row {
        spacing: Theme.gapS
        ActionButton {
          width: (runView.width - Theme.gapS) / 2
          label: "+1 min"
          fill: Theme.surfaceAlt
          onClicked: root.timerState.addMinute()
        }
        ActionButton {
          width: (runView.width - Theme.gapS) / 2
          label: "Cancel"
          labelColor: Theme.critical
          fill: Theme.surfaceAlt
          onClicked: root.timerState.cancel()
        }
      }
    }
  }
}
