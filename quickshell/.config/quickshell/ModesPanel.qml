import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: panel
  required property string ownerScreen
  // Mode whose row shows the custom-duration box instead of the presets.
  property string customMode: ""
  // Mode whose custom duration is running. Its box closes only if that
  // command succeeds and the box is still the one open, so a rejected entry
  // stays editable beside the error banner.
  property string customPending: ""

  // Every close path (Escape, scrim, keybind, SUPER+Q) lands here.
  onVisibleChanged: if (!visible) { customMode = ""; customPending = ""; ModesState.actionError = "" }

  Connections {
    target: ModesState
    function onActionFinished(ok) {
      const submitted = panel.customPending
      panel.customPending = ""
      if (ok && submitted !== "" && panel.customMode === submitted) {
        panel.customMode = ""
        card.forceActiveFocus()
      }
    }
  }

  visible: ModesState.panelVisible && ModesState.panelScreen === ownerScreen
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-desktop-modes"

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.scrimOpacity)
    MouseArea { anchors.fill: parent; onClicked: ModesState.close() }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(Theme.fs(720), panel.width - 2 * Theme.menuOuterMargin)
    height: Math.min(Theme.fs(520), panel.height - 2 * Theme.menuOuterMargin)
    radius: Theme.menuRadius
    color: Theme.bg
    border.width: Theme.menuBorderWidth
    border.color: Theme.borderActive1
    focus: true
    Keys.onEscapePressed: ModesState.close()
    MouseArea { anchors.fill: parent }

    Column {
      anchors.fill: parent
      anchors.margins: Theme.menuPadding
      spacing: Theme.gapM

      Text {
        text: "Desktop modes"
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.menuFontTitle
        font.bold: true
      }
      Text {
        width: parent.width
        text: "Turn a mode on until you switch it off, or for a set time."
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.menuFontBody
      }
      Text {
        visible: ModesState.actionError !== "" || ModesState.lastError !== "" || !ModesState.daemonRunning
        width: parent.width
        text: ModesState.actionError || ModesState.lastError || "Expiry daemon is not running; untimed controls still work."
        color: Theme.warning
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.menuFontBody
      }

      Repeater {
        model: ["night-light", "do-not-disturb", "stay-awake", "screensaver-auto"]
        Rectangle {
          id: modeRow
          required property var modelData
          readonly property var status: ModesState.mode(modelData)
          readonly property var meta: ModesState.metadata[modelData]
          readonly property bool timed: modelData !== "screensaver-auto"
          readonly property bool editing: panel.customMode === modelData
          width: card.width - 2 * Theme.menuPadding
          height: Theme.fs(70)
          radius: Theme.radiusCell
          color: Theme.surface
          opacity: status.available ? 1 : Theme.opacityUnavailable

          Row {
            anchors.fill: parent
            anchors.margins: Theme.gapM
            spacing: Theme.gapM
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modeRow.meta.glyph
              color: modeRow.status.error ? Theme.critical : Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(22)
            }
            Column {
              id: labelColumn
              // Takes whatever the glyph, switch and duration controls leave.
              width: parent.width - x - modeControls.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              Text { text: modeRow.meta.label; color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(14) }
              Text {
                width: parent.width
                elide: Text.ElideRight
                text: modeRow.status.error
                  || (modeRow.status.observed && modeRow.status.expires_at
                      ? "Until " + ModesState.clockTime(modeRow.status.expires_at)
                      : modeRow.meta.detail)
                color: modeRow.status.error ? Theme.critical : Theme.textMuted
                font.pixelSize: Theme.fs(11)
              }
            }
            Row {
              id: modeControls
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.gapM
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fs(58); height: Theme.fs(28); radius: Theme.radiusCell
                color: modeRow.status.observed ? Theme.accent : Theme.surfaceAlt
                Text {
                  anchors.centerIn: parent
                  text: modeRow.status.observed ? "ON" : "OFF"
                  color: modeRow.status.observed ? Theme.onAccent : Theme.text
                  font.bold: true; font.pixelSize: Theme.fs(11)
                }
                MouseArea {
                  anchors.fill: parent
                  enabled: modeRow.status.available
                  onClicked: ModesState.toggle(modeRow.modelData)
                }
              }
              Repeater {
                model: modeRow.timed && !modeRow.editing ? ModesState.durationPresets : []
                Rectangle {
                  required property string modelData
                  width: Theme.fs(42); height: Theme.fs(28); radius: Theme.radiusCell
                  color: Theme.surfaceAlt
                  Text { anchors.centerIn: parent; text: parent.modelData; color: Theme.text; font.pixelSize: Theme.fs(10) }
                  MouseArea {
                    anchors.fill: parent
                    enabled: modeRow.status.available
                    onClicked: ModesState.timed(modeRow.modelData, parent.modelData)
                  }
                }
              }
              Rectangle {
                visible: modeRow.timed && !modeRow.editing
                width: Theme.fs(58); height: Theme.fs(28); radius: Theme.radiusCell
                color: Theme.surfaceAlt
                Text { anchors.centerIn: parent; text: "Custom"; color: Theme.text; font.pixelSize: Theme.fs(10) }
                MouseArea {
                  anchors.fill: parent
                  enabled: modeRow.status.available
                  onClicked: panel.customMode = modeRow.modelData
                }
              }
              Rectangle {
                // Same footprint as the presets plus Custom, so the row
                // does not shift while typing.
                visible: modeRow.editing
                width: ModesState.durationPresets.length * (Theme.fs(42) + Theme.gapM) + Theme.fs(58)
                height: Theme.fs(28); radius: Theme.radiusCell
                color: Theme.surfaceAlt
                border.width: 1
                border.color: Theme.accent
                TextInput {
                  id: customInput
                  anchors.fill: parent
                  anchors.leftMargin: Theme.gapM; anchors.rightMargin: Theme.gapM
                  verticalAlignment: TextInput.AlignVCenter
                  color: Theme.text
                  font.pixelSize: Theme.fs(11)
                  clip: true
                  // Digits plus h/m/s; the controller does the real parsing.
                  validator: RegularExpressionValidator { regularExpression: /[0-9hmsHMS ]{0,12}/ }
                  onVisibleChanged: {
                    text = ""
                    if (visible) forceActiveFocus()
                  }
                  onTextEdited: ModesState.actionError = ""
                  onAccepted: {
                    if (text.trim() === "" || panel.customPending !== "") return
                    // Busy with another action: keep the text, Enter again.
                    if (ModesState.timed(modeRow.modelData, text.trim()))
                      panel.customPending = modeRow.modelData
                  }
                  Keys.onEscapePressed: event => {
                    panel.customPending = ""
                    panel.customMode = ""
                    card.forceActiveFocus()
                    event.accepted = true
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: customInput.text === ""
                    text: "How long? 45m, 2h, 1h30m · Enter"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fs(11)
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.width; height: Theme.fs(36); radius: Theme.radiusCell; color: Theme.accent
        Text { anchors.centerIn: parent; text: "Start screensaver now"; color: Theme.onAccent; font.bold: true }
        MouseArea { anchors.fill: parent; onClicked: { ModesState.close(); ModesState.screensaver() } }
      }
    }
  }
}
