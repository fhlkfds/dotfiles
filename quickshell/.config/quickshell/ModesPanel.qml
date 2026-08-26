import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: panel
  required property string ownerScreen

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
    width: Math.min(Theme.fs(620), panel.width - 2 * Theme.menuOuterMargin)
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
        text: "Temporary session behavior. Locking, suspend, display power, and indicators remain independent."
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.menuFontBody
      }
      Text {
        visible: ModesState.lastError !== "" || !ModesState.daemonRunning
        width: parent.width
        text: ModesState.lastError !== "" ? ModesState.lastError : "Expiry daemon is not running; untimed controls still work."
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
              width: Theme.fs(240)
              anchors.verticalCenter: parent.verticalCenter
              Text { text: modeRow.meta.label; color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(14) }
              Text {
                text: modeRow.status.error || modeRow.meta.detail
                color: modeRow.status.error ? Theme.critical : Theme.textMuted
                font.pixelSize: Theme.fs(11)
              }
            }
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
              model: modeRow.modelData === "screensaver-auto" ? [] : ModesState.durationPresets
              Rectangle {
                required property string modelData
                width: Theme.fs(42); height: Theme.fs(28); radius: Theme.radiusCell
                color: Theme.surfaceAlt
                Text { anchors.centerIn: parent; text: parent.modelData; color: Theme.text; font.pixelSize: Theme.fs(10) }
                MouseArea {
                  anchors.fill: parent
                  onClicked: ModesState.timed(modeRow.modelData, parent.modelData)
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
