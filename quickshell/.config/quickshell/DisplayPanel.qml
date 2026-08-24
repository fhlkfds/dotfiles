import QtQuick
import Quickshell

// Display panel: per-monitor brightness, shell/GTK text size, monitor scale.
//
// Layout follows the other panels in this shell (AudioPanel / NetworkPanel) and
// reuses their palette via Theme, so it does not read as a visual outlier.
PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  // Only the bar instance whose icon was clicked shows a panel.
  visible: DisplayState.panelVisible
        && DisplayState.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  implicitWidth: Theme.fs(320)
  implicitHeight: layout.implicitHeight + Theme.panelMargin * 2

  readonly property var mon: DisplayState.selected
  readonly property bool multi: DisplayState.monitors.length > 1

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    Item {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: DisplayState.panelVisible = false

      Column {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.panelMargin
        spacing: Theme.sectionSpacing

        // --- HEADER ---
        Item {
          width: parent.width
          height: Math.max(headerIcon.implicitHeight, headerText.implicitHeight)

          Text {
            id: headerIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: DisplayState.glyph
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(20)
            color: Theme.text
          }

          Column {
            id: headerText
            anchors.left: headerIcon.right
            anchors.leftMargin: Theme.fs(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
              text: "Display"
              color: Theme.text
              font.bold: true
              font.pixelSize: Theme.fs(15)
            }

            Text {
              text: {
                if (!panel.mon)
                  return "No monitor detected"
                if (!panel.mon.ddcOk)
                  return "DDC/CI UNAVAILABLE"
                return "DDC/CI BRIGHTNESS · " + panel.mon.brightness + "%"
              }
              color: panel.mon && panel.mon.ddcOk ? Theme.textDim : Theme.error
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }
          }
        }

        // --- MONITOR SELECTOR (only with more than one display) ---
        Rectangle {
          visible: panel.multi
          width: parent.width
          height: 1
          color: Theme.surface
        }

        Row {
          visible: panel.multi
          width: parent.width
          spacing: Theme.fs(4)

          Repeater {
            model: DisplayState.monitors

            Rectangle {
              required property var modelData
              readonly property bool isActive:
                DisplayState.selectedMonitor === modelData.name
              width: (parent.width - Theme.fs(4) * (DisplayState.monitors.length - 1))
                     / Math.max(1, DisplayState.monitors.length)
              height: Theme.fs(24)
              radius: Theme.radiusRow
              color: isActive ? Theme.accent : Theme.surface

              Text {
                anchors.centerIn: parent
                width: parent.width - Theme.fs(8)
                horizontalAlignment: Text.AlignHCenter
                text: modelData.name
                color: parent.isActive ? Theme.bgDeep : Theme.text
                font.pixelSize: Theme.fs(11)
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                onClicked: DisplayState.selectedMonitor = modelData.name
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        // --- BRIGHTNESS ---
        Column {
          width: parent.width
          spacing: Theme.itemSpacing

          Item {
            width: parent.width
            height: Theme.fs(14)

            Text {
              anchors.left: parent.left
              text: "BRIGHTNESS"
              color: Theme.textDim
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              text: panel.mon && panel.mon.ddcOk
                    ? panel.mon.brightness + "%" : "n/a"
              color: Theme.text
              font.pixelSize: Theme.fs(11)
            }
          }

          VolumeSlider {
            width: parent.width
            visible: panel.mon !== null && panel.mon.ddcOk
            value: DisplayState.brightnessFraction(panel.mon)
            onMoved: fraction =>
              DisplayState.setBrightnessFraction(DisplayState.selectedMonitor,
                                                 fraction)
          }

          Text {
            width: parent.width
            visible: panel.mon !== null && !panel.mon.ddcOk
            wrapMode: Text.WordWrap
            text: "This display does not answer DDC/CI, so its brightness "
                + "cannot be controlled from here."
            color: Theme.textMuted
            font.pixelSize: Theme.fs(11)
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        // --- THEME ---
        // A launcher, not a second picker: this opens the same fullscreen
        // gallery the Super+Ctrl+Shift+Space chord does, so there is one theme
        // UI and one backend. Appearance lives here because this panel is
        // already where the shell's look is adjusted (text size, scale).
        Rectangle {
          width: parent.width
          height: 1
          color: Theme.surface
        }

        Column {
          width: parent.width
          spacing: Theme.itemSpacing

          Text {
            text: "THEME"
            color: Theme.textDim
            font.pixelSize: Theme.fs(10)
            font.bold: true
          }

          Rectangle {
            id: themeRow
            width: parent.width
            height: Theme.fs(34)
            radius: Theme.radiusCell
            color: themeRowMouse.containsMouse
              ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
              : "transparent"
            border.width: Theme.borderWidth
            border.color: themeRowMouse.containsMouse
              ? Qt.rgba(Theme.borderActive1.r, Theme.borderActive1.g,
                        Theme.borderActive1.b, 0.35)
              : Theme.surface

            Text {
              id: themeGlyph
              anchors.left: parent.left
              anchors.leftMargin: Theme.fs(9)
              anchors.verticalCenter: parent.verticalCenter
              text: ThemeState.glyphPalette
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(13)
              color: Theme.accent
            }

            Text {
              anchors.left: themeGlyph.right
              anchors.leftMargin: Theme.fs(8)
              anchors.right: themeChevron.left
              anchors.rightMargin: Theme.fs(6)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: Theme.themeName
              color: Theme.text
              font.pixelSize: Theme.fs(12)
            }

            Text {
              id: themeChevron
              anchors.right: parent.right
              anchors.rightMargin: Theme.fs(9)
              anchors.verticalCenter: parent.verticalCenter
              text: "›"
              color: Theme.textMuted
              font.pixelSize: Theme.fs(15)
            }

            MouseArea {
              id: themeRowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                // This popup holds grabFocus, so it has to go before a
                // layer-shell overlay can take exclusive keyboard focus.
                DisplayState.panelVisible = false
                ThemeState.togglePanel(panel.ownerScreen)
              }
            }
          }
        }

        // --- TEXT SIZE ---
        Column {
          width: parent.width
          spacing: Theme.itemSpacing

          Item {
            width: parent.width
            height: Theme.fs(14)

            Text {
              anchors.left: parent.left
              text: "TEXT SIZE"
              color: Theme.textDim
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              text: Theme.fontScale.toFixed(2) + "x"
              color: Theme.text
              font.pixelSize: Theme.fs(11)
            }
          }

          Row {
            width: parent.width
            spacing: Theme.fs(4)

            Repeater {
              model: Theme.textScalePresets

              Rectangle {
                required property real modelData
                readonly property bool isActive:
                  Math.abs(Theme.fontScale - modelData) < 0.001
                width: (parent.width - Theme.fs(4)
                        * (Theme.textScalePresets.length - 1))
                       / Theme.textScalePresets.length
                height: Theme.fs(26)
                radius: Theme.radiusCell
                color: isActive ? Theme.accent : "transparent"
                border.width: Theme.borderWidth
                border.color: isActive ? Theme.accent : Theme.surface

                Text {
                  anchors.centerIn: parent
                  text: modelData + "x"
                  color: parent.isActive ? Theme.bgDeep : Theme.text
                  font.pixelSize: Theme.fs(11)
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: Theme.fontScale = modelData
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        // --- SCALE ---
        Column {
          width: parent.width
          spacing: Theme.itemSpacing

          Item {
            width: parent.width
            height: Theme.fs(14)

            Text {
              anchors.left: parent.left
              text: "SCALE"
              color: Theme.textDim
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              text: panel.mon ? panel.mon.scale.toFixed(2) + "x" : "n/a"
              color: Theme.text
              font.pixelSize: Theme.fs(11)
            }
          }

          Row {
            width: parent.width
            spacing: Theme.fs(4)

            Repeater {
              model: DisplayState.scalePresets

              Rectangle {
                required property real modelData
                readonly property bool isValid:
                  DisplayState.scaleValid(panel.mon, modelData)
                readonly property bool isActive: panel.mon
                  && Math.abs(panel.mon.scale - modelData) < 0.001
                width: (parent.width - Theme.fs(4)
                        * (DisplayState.scalePresets.length - 1))
                       / DisplayState.scalePresets.length
                height: Theme.fs(26)
                radius: Theme.radiusCell
                color: isActive ? Theme.accent : "transparent"
                border.width: Theme.borderWidth
                border.color: isActive ? Theme.accent : Theme.surface
                // Presets that would not divide this monitor's mode into whole
                // logical pixels are shown but not selectable.
                opacity: isValid ? 1 : Theme.opacityDisabled

                Text {
                  anchors.centerIn: parent
                  text: modelData + "x"
                  color: parent.isActive ? Theme.bgDeep : Theme.text
                  font.pixelSize: Theme.fs(11)
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: parent.isValid && !DisplayState.scaleBusy
                  onClicked: DisplayState.setScale(DisplayState.selectedMonitor,
                                                   modelData)
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: panel.mon !== null
            text: panel.mon
                  ? panel.mon.width + "x" + panel.mon.height + " → "
                    + Math.round(panel.mon.width / panel.mon.scale) + "x"
                    + Math.round(panel.mon.height / panel.mon.scale)
                    + " logical"
                  : ""
            color: Theme.textMuted
            font.pixelSize: Theme.fs(10)
          }
        }

        // --- ERROR ---
        Text {
          width: parent.width
          visible: DisplayState.lastError !== ""
          wrapMode: Text.WordWrap
          text: DisplayState.lastError
          color: Theme.error
          font.pixelSize: Theme.fs(11)
        }
      }
    }
  }

  onVisibleChanged: {
    if (visible) {
      // Default the selector to the monitor this panel belongs to.
      if (DisplayState.monitorFor(panel.ownerScreen))
        DisplayState.selectedMonitor = panel.ownerScreen
      // Opening the panel is the user-triggered retry for a failed ddcutil
      // probe, so re-arm bus detection here.
      DisplayState.busMapStale = true
      DisplayState.refreshMonitors()
      focusScope.forceActiveFocus()
    }
  }
}
