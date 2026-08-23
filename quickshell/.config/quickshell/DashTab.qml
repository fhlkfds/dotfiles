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
