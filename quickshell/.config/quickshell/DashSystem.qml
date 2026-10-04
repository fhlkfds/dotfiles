import QtQuick
import Quickshell

// Dashboard system page: CPU, memory, storage, GPU and network from SysState,
// which polls only while the dashboard is open. Hardware the machine does not
// expose reads as unavailable rather than as a made-up number.
Item {
  id: root
  property bool live: false

  readonly property int gap: Theme.gapM
  readonly property int headerH: Theme.fs(38)
  readonly property int rowH: (height - headerH - gap * 2) / 2
  readonly property int wideW: Theme.fs(372)

  component Chip: Rectangle {
    id: chip
    property string glyph: ""
    property string label: ""
    property color glyphColor: Theme.accent
    implicitWidth: chipRow.implicitWidth + Theme.gapS * 2
    implicitHeight: Theme.fs(24)
    radius: Theme.radiusCell
    color: Theme.withAlpha(Theme.foreground, 0.06)
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Theme.gapXS
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.glyph
        color: chip.glyphColor
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        color: Theme.textDim
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
    }
  }

  // CPU and GPU share a layout: ring badge, name, big percentage, history.
  component UsageCard: DashCard {
    id: usage
    property string icon: ""
    property string label: ""
    property string model: ""
    property real value: 0
    property bool ok: true
    property string unavailableText: "unavailable"
    property var history: []
    default property alias extra: below.data

    Gauge {
      id: badge
      size: Theme.fs(40)
      thickness: Theme.fs(4)
      trackColor: Theme.withAlpha(Theme.foreground, 0.08)
      value: usage.ok ? usage.value : 0
      text: ""
    }
    Text {
      anchors.centerIn: badge
      text: usage.icon
      color: Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(16)
    }
    Column {
      anchors.left: badge.right
      anchors.leftMargin: Theme.gapS
      anchors.right: percent.left
      anchors.verticalCenter: badge.verticalCenter
      Text {
        text: usage.label
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(13)
        font.bold: true
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: usage.model !== "" ? usage.model : "unknown"
        color: Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
    }
    Text {
      id: percent
      anchors.right: parent.right
      anchors.verticalCenter: badge.verticalCenter
      text: usage.ok ? Math.round(usage.value * 100) + "%" : ""
      color: Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(26)
      font.bold: true
    }

    Text {
      anchors.centerIn: graph
      visible: !usage.ok
      text: usage.unavailableText
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(12)
    }
    Sparkline {
      id: graph
      anchors.top: badge.bottom
      anchors.topMargin: Theme.gapM
      anchors.bottom: below.top
      anchors.bottomMargin: Theme.gapS
      width: parent.width
      visible: usage.ok
      series: [{ values: usage.history, color: Theme.accent }]
    }
    Column {
      id: below
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Theme.gapS
    }
  }

  // Memory and storage: an open arc with the used share inside.
  component ArcCard: DashCard {
    id: arcCard
    property real value: 0
    property bool ok: true
    property string primary: ""
    property string secondary: ""

    Gauge {
      id: arc
      anchors.horizontalCenter: parent.horizontalCenter
      y: Theme.fs(4)
      size: Math.min(parent.width, parent.height - Theme.fs(44))
      thickness: Theme.fs(10)
      sweep: 270
      trackColor: Theme.withAlpha(Theme.foreground, 0.08)
      value: arcCard.value
      available: arcCard.ok
      text: ""
    }
    Column {
      anchors.centerIn: arc
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: arcCard.ok ? Math.round(arcCard.value * 100) + "%" : "n/a"
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(22)
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "used"
        color: Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
    }
    Column {
      anchors.bottom: parent.bottom
      width: parent.width
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: arcCard.primary
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
        font.bold: true
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: arcCard.secondary
        color: Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
    }
  }

  // ===================== header =====================

  Column {
    anchors.verticalCenter: header.verticalCenter
    Text {
      text: SysState.hostname
      color: Theme.text
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(16)
      font.bold: true
    }
    Text {
      text: SysState.kernel
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(11)
    }
  }

  Row {
    id: header
    anchors.right: parent.right
    height: root.headerH
    spacing: Theme.gapS
    Chip {
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: Theme.fs(28)
      glyph: String.fromCodePoint(0xf0150) // md-clock_outline
      label: SysState.uptimeSeconds > 0 ? SysState.fmtUptime(SysState.uptimeSeconds) : "--"
    }
    Chip {
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: Theme.fs(28)
      glyph: String.fromCodePoint(0xf03cc) // md-open_in_new
      label: "Mission Center"
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // run-or-install offers to install it when it is missing.
        onClicked: {
          Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/run-or-install", "missioncenter"])
          DashboardState.panelVisible = false
        }
      }
    }
  }

  // ===================== row 1 =====================

  UsageCard {
    id: cpuCard
    y: root.headerH + root.gap
    width: root.wideW
    height: root.rowH
    icon: String.fromCodePoint(0xf061a) // md-chip
    label: "CPU"
    model: SysState.cpuModel
    value: SysState.cpuPercent / 100
    ok: SysState.cpuSeeded
    unavailableText: "Measuring…"
    history: SysState.cpuHistory

    // One bar per logical CPU.
    Row {
      width: parent.width
      height: Theme.fs(16)
      spacing: Theme.fs(3)
      visible: SysState.coreUsage.length > 0
      Repeater {
        model: SysState.coreUsage.length
        Rectangle {
          required property int index
          width: (parent.width - parent.spacing * (SysState.coreUsage.length - 1)) / SysState.coreUsage.length
          height: parent.height
          radius: Theme.fs(3)
          color: Theme.withAlpha(Theme.foreground, 0.08)
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(Theme.fs(2), parent.height * (SysState.coreUsage[parent.index] || 0))
            radius: parent.radius
            color: Theme.accent
          }
        }
      }
    }
    Row {
      spacing: Theme.gapS
      Chip {
        glyph: String.fromCodePoint(0xf050f) // md-thermometer
        glyphColor: Theme.green
        label: SysState.cpuTempAvailable ? Math.round(SysState.cpuTempF) + "°F" : "n/a"
      }
      Chip {
        glyph: String.fromCodePoint(0xf04c5) // md-speedometer
        label: SysState.cpuFreqGhz > 0 ? SysState.cpuFreqGhz.toFixed(2) + " GHz" : "n/a"
      }
      Chip {
        glyph: String.fromCodePoint(0xf029a) // md-gauge
        label: SysState.loadAvg.toFixed(2)
      }
    }
  }

  ArcCard {
    x: cpuCard.width + root.gap
    y: cpuCard.y
    width: (root.width - x - root.gap) / 2
    height: root.rowH
    glyph: String.fromCodePoint(0xf035b) // md-memory
    title: "Memory"
    value: SysState.memFraction
    ok: SysState.memTotalBytes > 0
    primary: SysState.fmtGiB(SysState.memUsedBytes).replace(" GiB", "") + " / " + SysState.fmtGiB(SysState.memTotalBytes)
    secondary: "Swap " + SysState.fmtGiB(SysState.swapUsedBytes).replace(" GiB", "") + " / " + SysState.fmtGiB(SysState.swapTotalBytes)
  }

  ArcCard {
    x: root.width - width
    y: cpuCard.y
    width: (root.width - cpuCard.width - root.gap * 2) / 2
    height: root.rowH
    glyph: String.fromCodePoint(0xf02ca) // md-harddisk
    title: "Storage  /"
    value: SysState.diskFraction
    ok: SysState.diskTotalBytes > 0
    primary: SysState.fmtGiB(SysState.diskUsedBytes).replace(" GiB", "") + " / " + SysState.fmtGiB(SysState.diskTotalBytes)
    secondary: SysState.fmtGiB(SysState.diskTotalBytes - SysState.diskUsedBytes) + " free"
  }

  // ===================== row 2 =====================

  UsageCard {
    id: gpuCard
    y: root.height - height
    width: root.wideW
    height: root.rowH
    icon: String.fromCodePoint(0xf08ae) // md-expansion_card
    label: "GPU"
    model: SysState.gpuModel
    value: SysState.gpuPercent / 100
    ok: SysState.gpuAvailable && !SysState.gpuAsleep
    unavailableText: SysState.gpuAsleep ? "Asleep (power saving)" : "GPU stats unavailable"
    history: SysState.gpuHistory

    Row {
      spacing: Theme.gapS
      visible: gpuCard.ok
      Chip {
        glyph: String.fromCodePoint(0xf050f) // md-thermometer
        glyphColor: Theme.green
        label: SysState.gpuTempAvailable ? Math.round(SysState.gpuTempF) + "°F" : "n/a"
      }
      Chip {
        glyph: String.fromCodePoint(0xf035b) // md-memory
        label: SysState.gpuVramTotalBytes > 0
               ? SysState.fmtGiB(SysState.gpuVramUsedBytes).replace(" GiB", "") + " / " + SysState.fmtGiB(SysState.gpuVramTotalBytes)
               : "n/a"
      }
      Chip {
        glyph: String.fromCodePoint(0xf140b) // md-lightning_bolt
        glyphColor: Theme.yellow
        label: SysState.gpuPowerW >= 0 ? Math.round(SysState.gpuPowerW) + " W" : "n/a"
      }
    }
  }

  DashCard {
    x: gpuCard.width + root.gap
    y: gpuCard.y
    width: root.width - x
    height: root.rowH
    glyph: String.fromCodePoint(0xf0317) // md-lan
    title: "Network"

    trailing: Text {
      text: SysState.netIface
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(11)
    }

    Sparkline {
      anchors.top: parent.top
      anchors.bottom: rates.top
      anchors.bottomMargin: Theme.gapS
      width: parent.width
      maxValue: 0
      series: [{ values: SysState.txHistory, color: Theme.green },
               { values: SysState.rxHistory, color: Theme.accent }]
    }

    Row {
      id: rates
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Theme.gapS
      Repeater {
        model: [
          { glyph: 0xf072e, rate: "rx", word: "Down" },  // md-arrow_down_bold
          { glyph: 0xf0737, rate: "tx", word: "Up" }     // md-arrow_up_bold
        ]
        Rectangle {
          required property var modelData
          readonly property color tint: modelData.rate === "rx" ? Theme.accent : Theme.green
          width: (rates.width - rates.spacing) / 2
          height: Theme.fs(44)
          radius: Theme.radiusCell
          color: Theme.withAlpha(Theme.foreground, 0.05)
          Rectangle {
            id: arrow
            x: Theme.gapS
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fs(28)
            height: width
            radius: Theme.radiusCell
            color: Theme.withAlpha(parent.tint, 0.18)
            Text {
              anchors.centerIn: parent
              text: String.fromCodePoint(parent.parent.modelData.glyph)
              color: parent.parent.tint
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(14)
            }
          }
          Column {
            anchors.left: arrow.right
            anchors.leftMargin: Theme.gapS
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: SysState.fmtRate(parent.parent.modelData.rate === "rx" ? SysState.rxRate : SysState.txRate)
              color: Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(12)
              font.bold: true
            }
            Text {
              text: parent.parent.modelData.word + " · "
                    + SysState.fmtBytes(parent.parent.modelData.rate === "rx" ? SysState.rxTotal : SysState.txTotal)
              color: Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(10)
            }
          }
        }
      }
    }
  }
}
