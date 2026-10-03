import QtQuick

// System vitals drawn on the desktop: ring gauges for CPU, RAM, disk, CPU
// temperature and battery, with free RAM and disk spelled out underneath.
//
// Reads everything through `sys` and `battery` so the smoke harness can hand it
// stand-ins with the same shape as SysState and BatteryState.
Item {
  id: root

  property var sys: SysState
  property var battery: BatteryState

  readonly property int gaugeSize: Theme.fs(74)
  readonly property int padding: Theme.fs(22)
  readonly property int edgeMargin: Theme.fs(56)

  // This desktop has no system battery; the mouse is the only real one. A
  // laptop battery wins when there is one, and with neither the ring is gone
  // rather than showing an invented number.
  readonly property bool systemBattery: battery.hasBattery
  readonly property bool batteryShown: systemBattery || sys.mouseBatteryAvailable
  readonly property real batteryPercent: systemBattery ? battery.percent : sys.mouseBatteryPercent
  readonly property bool batteryCharging: systemBattery ? battery.charging : sys.mouseCharging
  readonly property string batteryLabel: systemBattery ? "BATTERY" : "MOUSE"

  readonly property real memFreeBytes: Math.max(0, sys.memTotalBytes - sys.memUsedBytes)
  readonly property real diskFreeBytes: Math.max(0, sys.diskTotalBytes - sys.diskUsedBytes)

  // "AMD Ryzen 9 5900X 12-Core Processor" -> "Ryzen 9 5900X".
  readonly property string cpuName: sys.cpuModel
    .replace(/^(AMD|Intel\(R\)|Intel)\s+/, "")
    .replace(/\(R\)|\(TM\)/g, "")
    .replace(/\s+\d+-Core Processor$/, "")
    .replace(/\s+(CPU\s+)?@.*$/, "")
    .trim()

  // Accent while comfortable, then the theme's warning and critical colours.
  function loadColor(fraction) {
    if (fraction >= 0.9) return Theme.critical
    if (fraction >= 0.75) return Theme.warning
    return Theme.accent
  }

  // Tctl on a Ryzen idles in the 40s and throttles at 90 C.
  function tempColor(celsius) {
    if (celsius >= 85) return Theme.critical
    if (celsius >= 70) return Theme.warning
    return Theme.accent
  }

  function batteryColor(percent, charging) {
    if (charging) return Theme.success
    if (percent <= 15) return Theme.critical
    if (percent <= 30) return Theme.warning
    return Theme.accent
  }

  // The ring spans room temperature to the throttle point.
  function tempFraction(celsius) {
    return (celsius - 25) / (95 - 25)
  }

  implicitWidth: layout.implicitWidth + padding * 2
  implicitHeight: layout.implicitHeight + padding * 2

  // Translucent slab over the wallpaper, in the bar's own background colour so
  // it reads as part of the shell rather than a separate app.
  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusL
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.82)
    border.width: Theme.borderWidth
    border.color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.12)
  }

  Column {
    id: layout
    anchors.centerIn: parent
    spacing: Theme.fs(16)

    // --- header ----------------------------------------------------------------

    Item {
      width: gauges.implicitWidth
      height: Math.max(title.implicitHeight, model.implicitHeight)

      Text {
        id: title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "VITALS"
        color: Theme.accent
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(13)
        font.bold: true
        font.letterSpacing: Theme.fs(4)
      }

      Text {
        id: model
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - title.implicitWidth - Theme.gapL)
        text: root.cpuName
        color: Theme.textMuted
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(12)
        elide: Text.ElideRight
      }
    }

    // --- rings -----------------------------------------------------------------

    Row {
      id: gauges
      spacing: Theme.fs(20)

      Vital {
        id: cpuGauge
        label: "CPU"
        // The first sample only seeds the delta, so there is no reading yet.
        available: root.sys.cpuSeeded
        value: root.sys.cpuPercent / 100
        text: Math.round(root.sys.cpuPercent) + "%"
        ringColor: root.loadColor(value)
      }

      Vital {
        id: ramGauge
        label: "RAM"
        available: root.sys.memTotalBytes > 0
        value: root.sys.memFraction
        text: Math.round(value * 100) + "%"
        ringColor: root.loadColor(value)
      }

      Vital {
        id: diskGauge
        label: "DISK"
        available: root.sys.diskTotalBytes > 0
        value: root.sys.diskFraction
        text: Math.round(value * 100) + "%"
        ringColor: root.loadColor(value)
      }

      Vital {
        id: tempGauge
        label: "TEMP"
        available: root.sys.cpuTempAvailable && root.sys.cpuTempC > 0
        value: root.tempFraction(root.sys.cpuTempC)
        text: Math.round(root.sys.cpuTempF) + "°F"
        ringColor: root.tempColor(root.sys.cpuTempC)
      }

      Vital {
        id: batteryGauge
        visible: root.batteryShown
        label: root.batteryLabel
        charging: root.batteryCharging
        value: root.batteryPercent / 100
        text: Math.round(root.batteryPercent) + "%"
        ringColor: root.batteryColor(root.batteryPercent, root.batteryCharging)
      }
    }

    // --- footer ----------------------------------------------------------------

    Rectangle {
      width: gauges.implicitWidth
      height: 1
      color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.10)
    }

    Item {
      width: gauges.implicitWidth
      height: footerLeft.implicitHeight

      Row {
        id: footerLeft
        anchors.left: parent.left
        spacing: Theme.fs(18)

        Stat {
          id: ramFree
          figure: root.sys.memTotalBytes > 0 ? root.sys.fmtBytes(root.memFreeBytes) : "—"
          caption: "RAM free"
        }

        Stat {
          id: diskFree
          figure: root.sys.diskTotalBytes > 0 ? root.sys.fmtBytes(root.diskFreeBytes) : "—"
          caption: "disk free"
        }
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: footerLeft.verticalCenter
        visible: root.sys.uptimeSeconds > 0
        text: "up " + root.sys.fmtUptime(root.sys.uptimeSeconds)
        color: Theme.textMuted
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(12)
      }
    }
  }

  // One ring with its caption underneath.
  component Vital: Column {
    id: vital
    property string label: ""
    property alias value: ring.value
    property alias text: ring.text
    property alias ringColor: ring.ringColor
    property alias available: ring.available
    property bool charging: false

    spacing: Theme.fs(8)

    Gauge {
      id: ring
      anchors.horizontalCenter: parent.horizontalCenter
      size: root.gaugeSize
      thickness: Theme.fs(6)
      textSize: Theme.fs(16)
      trackColor: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.12)
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Theme.fs(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: vital.charging
        text: String.fromCodePoint(0xf140b)  // md-lightning-bolt
        color: Theme.success
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: vital.label
        color: Theme.textDim
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(11)
        font.bold: true
        font.letterSpacing: Theme.fs(2)
      }
    }
  }

  // A figure with a quiet caption after it: "12 GB RAM free".
  component Stat: Row {
    id: stat
    property string figure: ""
    property string caption: ""
    spacing: Theme.fs(6)

    Text {
      id: figureText
      text: stat.figure
      color: Theme.text
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(14)
      font.bold: true
    }

    Text {
      anchors.baseline: figureText.baseline
      text: stat.caption
      color: Theme.textMuted
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(12)
    }
  }
}
