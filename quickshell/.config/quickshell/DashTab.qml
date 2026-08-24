import QtQuick

// Overview page. Declares its own intrinsic size from tokens and never reads the
// drawer's dimensions -- that one-way dependency is what lets the drawer animate
// to each page's natural size without a binding loop.
Item {
  id: root
  implicitWidth: Theme.dashPageW
  implicitHeight: Theme.dashPageH

  Column {
    x: 0
    y: 0
    spacing: Theme.gapM

    // --- row 1: weather + profile ---
    Row {
      spacing: Theme.gapM

      WeatherMiniCard {}

      ProfileCard {
        // Fill the rest of the row so the page keeps its declared width.
        implicitWidth: root.implicitWidth - Theme.weatherCardW - Theme.gapM
      }
    }

    // --- row 2: date/time, media preview, resource rings ---
    Row {
      spacing: Theme.gapM

      DateTimeCard {}

      MediaPreviewCard {}

      Card {
        title: "RESOURCES"
        radius: Theme.radiusXL
        implicitWidth: root.implicitWidth - Theme.dateCardW
                       - Theme.mediaPreviewW - Theme.gapM * 2
        implicitHeight: Theme.dateCardH

        Grid {
          columns: 2
          columnSpacing: Theme.gapM
          rowSpacing: Theme.gapS

          Gauge {
            size: Theme.fs(64)
            trackColor: Theme.bgDeep
            value: SysState.cpuPercent / 100
            available: SysState.cpuSeeded
            text: Math.round(SysState.cpuPercent) + "%"
            label: "CPU"
          }
          Gauge {
            size: Theme.fs(64)
            trackColor: Theme.bgDeep
            value: SysState.memFraction
            available: SysState.memTotalBytes > 0
            text: Math.round(SysState.memFraction * 100) + "%"
            label: "RAM"
          }
          Gauge {
            size: Theme.fs(64)
            trackColor: Theme.bgDeep
            value: SysState.diskFraction
            available: SysState.diskTotalBytes > 0
            text: Math.round(SysState.diskFraction * 100) + "%"
            label: "Disk"
          }
          Gauge {
            size: Theme.fs(64)
            trackColor: Theme.bgDeep
            value: SysState.gpuPercent / 100
            available: SysState.gpuAvailable
            text: Math.round(SysState.gpuPercent) + "%"
            label: "GPU"
          }
        }
      }
    }

    // --- row 3: calendar ---
    // Second entry point to the web app manager, so it is discoverable without
    // knowing the keybinding. Opens the same overlay Super+Shift+A does.
    Card {
      id: webappCard
      title: "WEB APPS"
      radius: Theme.radiusXL
      implicitWidth: root.implicitWidth
      implicitHeight: Theme.fs(64)

      Item {
        anchors.fill: parent

        Text {
          id: webappGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: WebAppState.glyphWeb
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(20)
          color: Theme.accent
        }

        Text {
          anchors.left: webappGlyph.right
          anchors.leftMargin: Theme.gapM
          anchors.right: webappChevron.left
          anchors.rightMargin: Theme.gapM
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: {
            const n = WebAppState.apps.length
            if (n === 0)
              return "Turn a website into an app"
            return n + (n === 1 ? " web app installed" : " web apps installed")
          }
          color: Theme.text
          font.pixelSize: Theme.fs(12)
        }

        Text {
          id: webappChevron
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "\u203a"
          color: Theme.textMuted
          font.pixelSize: Theme.fs(16)
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            // The dashboard drawer holds focus, so it has to close before a
            // layer-shell overlay can take exclusive keyboard focus.
            DashboardState.panelVisible = false
            WebAppState.togglePanel(DashboardState.panelScreen)
          }
        }
      }
    }

    Card {
      title: "CALENDAR"
      radius: Theme.radiusXL
      implicitWidth: root.implicitWidth
      implicitHeight: Theme.calendarCardH

      // The shared grid, also used by the bar clock's CalendarPopup.
      CalendarGrid {
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
  }
}
