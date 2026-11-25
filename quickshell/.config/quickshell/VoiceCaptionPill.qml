import QtQuick

// The caption pill. Takes its state as a property so the smoke can load it
// with a fake; VoiceCaptionPopup passes the VoiceCaptionState singleton. The
// caption carries visible, phase, settled, pending, hint and level.
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

  function hex(c) {
    function h(v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2) }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }
  function escapeMarkup(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;")
  }
  readonly property string markup: {
    const c = caption
    let out = ""
    if (c.settled !== "")
      out += "<font color=\"" + hex(Theme.foregroundBright) + "\">" + escapeMarkup(c.settled) + "</font>"
    if (c.pending !== "")
      out += "<font color=\"" + hex(Theme.textMuted) + "\">" + escapeMarkup(c.pending) + "</font>"
    if (c.hint !== "")
      out += (out !== "" ? " " : "") + "<font color=\"" + hex(Theme.textMuted) + "\">" + escapeMarkup(c.hint) + "</font>"
    return out
  }

  // Plain bindings rather than a layout, so sizes settle without a window
  // polish pass and the headless smoke sees the real geometry.
  readonly property real maxWordsWidth: Theme.fs(720) - glyph.implicitWidth - Theme.gapS - meter.width - Theme.gapM

  implicitWidth: Theme.gapL * 2 + glyph.implicitWidth + Theme.gapS + meter.width + Theme.gapM + wordWindow.width
  implicitHeight: Theme.gapM * 2 + Math.max(glyph.implicitHeight, wordWindow.height)

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
    id: natural
    visible: false
    text: pill.markup
    textFormat: Text.StyledText
    font: words.font
  }

  FontMetrics { id: metrics; font: words.font }

  // Newest words stay visible: the text wraps freely and is pinned to the
  // bottom of a two-line window, so older lines scroll off the top.
  Item {
    id: wordWindow
    objectName: "captionWindow"
    x: meter.x + meter.width + Theme.gapM
    y: Theme.gapM
    width: Math.min(natural.implicitWidth, pill.maxWordsWidth)
    height: Math.min(words.implicitHeight, metrics.lineSpacing * 2)
    clip: true

    Text {
      id: words
      objectName: "captionWords"
      width: parent.width
      anchors.bottom: parent.bottom
      text: pill.markup
      textFormat: Text.StyledText
      wrapMode: Text.WordWrap
      opacity: pill.dimmed ? 0.5 : 1
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(18)
      font.weight: Font.Medium
    }
  }
}
