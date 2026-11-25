import QtQuick
import QtQuick.Layouts

// The caption pill. Takes its state as a property so the smoke can load it
// with a fake; VoiceCaptionPopup passes the VoiceCaptionState singleton. The
// caption carries visible, phase, settled, pending and hint.
Rectangle {
  id: pill
  required property var caption

  readonly property real targetOpacity: caption.visible ? Theme.surfaceOpacity : 0
  readonly property bool dimmed: caption.phase === "typing"

  implicitWidth: Math.min(content.implicitWidth, Theme.fs(720)) + Theme.gapL * 2
  implicitHeight: content.implicitHeight + Theme.gapM * 2
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

  RowLayout {
    id: content
    anchors.centerIn: parent
    width: Math.min(implicitWidth, Theme.fs(720))
    spacing: Theme.gapM

    Text {
      Layout.alignment: Qt.AlignTop
      text: String.fromCodePoint(0xf036c) // md-microphone
      color: Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(22)
    }

    Text {
      id: words
      Layout.fillWidth: true
      Layout.maximumWidth: Theme.fs(720) - Theme.fs(22) - Theme.gapM
      text: pill.markup
      textFormat: Text.StyledText
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      opacity: pill.dimmed ? 0.5 : 1
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(18)
      font.weight: Font.Medium
    }
  }
}
