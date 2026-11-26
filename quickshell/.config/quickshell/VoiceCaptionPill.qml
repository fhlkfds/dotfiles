import QtQuick

// The dictation pill: a microphone and a level meter. The words themselves are
// typed into the text box, so the pill only says that dictation is on, plus a
// hint when live words cannot work. Takes its state as a property so the smoke
// can load it with a fake; VoiceCaptionPopup passes the VoiceCaptionState
// singleton. The caption carries visible, phase, hint and level.
Rectangle {
  id: pill
  required property var caption

  readonly property real targetOpacity: caption.visible ? Theme.surfaceOpacity : 0
  readonly property bool dimmed: caption.phase === "typing"
  // The daemon maps -60..0 dBFS to 0..1. Room noise sits near 0.3 and loud
  // speech near 0.85, so that band fills the meter.
  readonly property real meterDrive: Math.max(0, Math.min(1, (caption.level - 0.3) / 0.55))

  radius: Math.min(height / 2, Theme.fs(22))
  color: Theme.background
  border.width: Math.max(1, Theme.borderWidth)
  border.color: Theme.borderAccent
  opacity: targetOpacity
  Behavior on opacity {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  // Plain bindings rather than a layout, so sizes settle without a window
  // polish pass and the headless smoke sees the real geometry.
  implicitWidth: Theme.gapL * 2 + glyph.implicitWidth + Theme.gapS + meter.width
    + (hint.visible ? Theme.gapM + hint.implicitWidth : 0)
  implicitHeight: Theme.gapM * 2 + Math.max(glyph.implicitHeight, hint.implicitHeight)

  Text {
    id: glyph
    x: Theme.gapL
    y: Theme.gapM
    text: String.fromCodePoint(0xf036c) // md-microphone
    color: Theme.accent
    font.family: Theme.glyphFamily
    font.pixelSize: Theme.fs(22)
  }

  // Live mic level: five bars, tallest in the middle, that grow with loudness.
  Item {
    id: meter
    objectName: "captionMeter"
    readonly property var weights: [0.5, 0.8, 1, 0.8, 0.5]
    readonly property real barWidth: Theme.fs(3)
    readonly property real barGap: Theme.fs(2)
    readonly property real minBar: Theme.fs(3)
    x: glyph.x + glyph.implicitWidth + Theme.gapS
    y: glyph.y + (glyph.implicitHeight - height) / 2
    width: weights.length * barWidth + (weights.length - 1) * barGap
    height: Theme.fs(18)

    Repeater {
      model: meter.weights
      Rectangle {
        required property int index
        required property real modelData
        readonly property real targetHeight: meter.minBar + (meter.height - meter.minBar) * pill.meterDrive * modelData
        objectName: "meterBar"
        x: index * (meter.barWidth + meter.barGap)
        anchors.verticalCenter: parent.verticalCenter
        width: meter.barWidth
        height: targetHeight
        radius: width / 2
        color: pill.caption.phase === "listening" ? Theme.accent : Theme.textMuted
        opacity: pill.dimmed ? 0.5 : 1
        Behavior on height {
          NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
        }
      }
    }
  }

  Text {
    id: hint
    objectName: "captionHint"
    visible: text !== ""
    x: meter.x + meter.width + Theme.gapM
    y: glyph.y + (glyph.implicitHeight - implicitHeight) / 2
    text: pill.caption.hint
    textFormat: Text.PlainText
    color: Theme.textMuted
    opacity: pill.dimmed ? 0.5 : 1
    font.family: Theme.uiFamily
    font.pixelSize: Theme.fs(18)
    font.weight: Font.Medium
  }
}
