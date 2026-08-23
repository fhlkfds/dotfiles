import QtQuick

// Performance page. Intrinsic size from tokens; cards are fixed-size so the page
// never depends on the drawer.
//
// Absent hardware is omitted entirely (no NVIDIA card -- nouveau exposes no
// utilisation, and no system battery). Transient failures show a dimmed card.
Item {
  id: root
  implicitWidth: Theme.perfPageW
  implicitHeight: Theme.perfPageH

  Column {
    x: 0
    y: 0
    spacing: Theme.gapM

    // --- hero cards ---
    Row {
      spacing: Theme.gapM

      HeroGauge {
        label: "CPU"
        model: SysState.cpuModel
        value: SysState.cpuPercent / 100
        valueText: Math.round(SysState.cpuPercent) + "%"
        tempF: SysState.cpuTempF
        tempAvailable: SysState.cpuTempAvailable
      }

      HeroGauge {
        label: "GPU"
        model: SysState.gpuModel
        value: SysState.gpuPercent / 100
        valueText: Math.round(SysState.gpuPercent) + "%"
        tempF: SysState.gpuTempF
        tempAvailable: SysState.gpuTempPath !== ""
        unavailable: !SysState.gpuAvailable
        unavailableText: "GPU stats unavailable"
      }

      // Uptime / host summary fills the rest of the hero row.
      Card {
        title: "SYSTEM"
        radius: Theme.radiusXL
        implicitWidth: root.implicitWidth - Theme.heroCardW * 2 - Theme.gapM * 2
        implicitHeight: Theme.heroCardH

        Column {
          anchors.left: parent.left
          anchors.top: parent.top
          spacing: 1

          Text {
            text: SysState.fmtUptime(SysState.uptimeSeconds)
            color: Theme.text
            font.pixelSize: Theme.fs(26)
            font.bold: true
          }
          Text {
            text: "uptime"
            color: Theme.textMuted
            font.pixelSize: Theme.fs(10)
          }
          Item { width: 1; height: Theme.gapM }
          Text {
            text: "Arch Linux"
            color: Theme.textDim
            font.pixelSize: Theme.fs(12)
          }
          Text {
            text: "liam@Kelper"
            color: Theme.textMuted
            font.pixelSize: Theme.fs(11)
          }
        }
      }
    }

    // --- small cards ---
    Row {
      spacing: Theme.gapM

      MetricCard {
        label: "MEMORY"
        glyph: String.fromCodePoint(0xf035b) // md-memory
        primary: SysState.fmtBytes(SysState.memUsedBytes) + " / "
                 + SysState.fmtBytes(SysState.memTotalBytes)
        fraction: SysState.memFraction
        secondary: SysState.fmtBytes(SysState.memTotalBytes - SysState.memUsedBytes)
                   + " available"
      }

      MetricCard {
        label: "STORAGE"
        glyph: String.fromCodePoint(0xf02ca) // md-harddisk
        primary: SysState.fmtBytes(SysState.diskUsedBytes) + " / "
                 + SysState.fmtBytes(SysState.diskTotalBytes)
        fraction: SysState.diskFraction
        secondary: SysState.fmtBytes(SysState.diskTotalBytes - SysState.diskUsedBytes)
                   + " free"
      }

      MetricCard {
        label: "NETWORK"
        glyph: String.fromCodePoint(0xf0317) // md-lan
        showBar: false
        primary: String.fromCodePoint(0xf0045) + " "
                 + NetworkState.formatBytes(NetworkState.rxRate) + "/s"
        secondary: String.fromCodePoint(0xf005d) + " "
                   + NetworkState.formatBytes(NetworkState.txRate) + "/s"
                   + "\n" + (NetworkState.iface !== "" ? NetworkState.iface : "no interface")
      }

      // Real peripheral battery. Hidden entirely when the mouse is absent --
      // deliberately not defaulted to a fabricated percentage.
      MetricCard {
        visible: SysState.mouseBatteryAvailable
        label: "MOUSE"
        glyph: String.fromCodePoint(0xf037d) // md-mouse
        primary: Math.round(SysState.mouseBatteryPercent) + "%"
        fraction: SysState.mouseBatteryPercent / 100
        secondary: SysState.mouseBatteryModel
                   + (SysState.mouseCharging ? "\ncharging" : "")
      }

      MetricCard {
        label: "POWER"
        glyph: String.fromCodePoint(0xf06a5) // md-power_plug
        showBar: false
        primary: SysState.onBattery ? "On battery" : "AC Power"
        secondary: "desktop · no system battery"
      }
    }
  }
}
