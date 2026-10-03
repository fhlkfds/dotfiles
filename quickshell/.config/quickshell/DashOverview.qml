import QtQuick
import "Holidays.js" as Holidays

// Dashboard overview: clock, weather, calendar, now playing, and a strip of
// system rings. Fills the fixed page size DashboardView gives it.
Item {
  id: root
  property bool live: false

  readonly property int gap: Theme.gapM
  readonly property int colA: Theme.fs(220)
  readonly property int colC: Theme.fs(224)
  readonly property int colB: width - colA - colC - gap * 2
  readonly property int stripH: Theme.fs(76)
  readonly property int topH: height - stripH - gap

  readonly property date now: ClockState.zonedDate()
  // Changes once a day rather than once a second, so the calendar and the
  // holiday countdown re-evaluate only at midnight.
  readonly property string dayKey: Qt.formatDate(now, "yyyy-MM-dd")
  readonly property date today: Date.fromLocaleString(Qt.locale(), dayKey, "yyyy-MM-dd")
  // The spectrum only while this page is on screen; otherwise a constant, so
  // the bars stop re-evaluating at cava's 30 fps.
  readonly property var levels: live && MediaState.isPlaying && CavaState.available ? CavaState.levels : []

  function isoWeek(d) {
    const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
    date.setUTCDate(date.getUTCDate() + 3 - (date.getUTCDay() + 6) % 7)
    const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 4))
    return 1 + Math.round(((date - yearStart) / 86400000 - 3 + (yearStart.getUTCDay() + 6) % 7) / 7)
  }
  function dayOfYear(d) {
    return Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate())
                       - new Date(d.getFullYear(), 0, 1)) / 86400000) + 1
  }
  function daysInYear(y) { return new Date(y, 1, 29).getMonth() === 1 ? 366 : 365 }

  component Chip: Rectangle {
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
        text: parent.parent.glyph
        color: parent.parent.glyphColor
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: parent.parent.label
        color: Theme.textDim
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
    }
  }

  component Ring: Item {
    id: ring
    property string label: ""
    property string sub: ""
    property real value: 0
    property bool ok: true
    width: parent.width / 5
    height: parent.height
    Row {
      anchors.centerIn: parent
      spacing: Theme.gapS
      Gauge {
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.fs(44)
        thickness: Theme.fs(5)
        trackColor: Theme.withAlpha(Theme.foreground, 0.08)
        value: ring.value
        available: ring.ok
        text: Math.round(ring.value * 100) + "%"
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: ring.label
          color: Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(12)
          font.bold: true
        }
        Text {
          text: ring.sub
          color: Theme.textMuted
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(10)
        }
      }
    }
  }

  component Tile: Rectangle {
    property string glyph: ""
    property string label: ""
    property string value: ""
    radius: Theme.radiusCell
    color: Theme.withAlpha(Theme.foreground, 0.05)
    Column {
      anchors.left: parent.left
      anchors.leftMargin: Theme.gapS
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.fs(2)
      Text {
        text: parent.parent.glyph + " " + parent.parent.label
        color: Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
      Text {
        text: parent.parent.value
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(14)
        font.bold: true
      }
    }
  }

  // ===================== column A: clock + weather =====================

  DashCard {
    id: clockCard
    width: root.colA
    height: Theme.fs(150)

    Column {
      anchors.fill: parent
      spacing: Theme.gapXS

      Row {
        spacing: Theme.gapXS
        Text {
          id: bigTime
          // "h" is only 12-hour when "AP" is in the same format string.
          text: Qt.formatDateTime(root.now, "h:mm AP").split(" ")[0]
          color: Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(48)
          font.bold: true
        }
        Column {
          anchors.bottom: bigTime.bottom
          anchors.bottomMargin: Theme.fs(9)
          Text {
            text: Qt.formatDateTime(root.now, "ss")
            color: Theme.accent
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(15)
            font.bold: true
          }
          Text {
            text: Qt.formatDateTime(root.now, "AP")
            color: Theme.textMuted
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(11)
          }
        }
      }
      Text {
        text: Qt.formatDateTime(root.now, "dddd, MMMM d")
        color: Theme.textDim
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
      }
      Item { width: 1; height: Theme.fs(2) }
      Row {
        spacing: Theme.gapS
        Chip {
          glyph: String.fromCodePoint(0xf0a33) // md-calendar_week
          label: "Week " + root.isoWeek(root.today)
        }
        Chip {
          glyph: String.fromCodePoint(0xf00f6) // md-calendar_today
          label: "Day " + root.dayOfYear(root.today) + "/" + root.daysInYear(root.today.getFullYear())
        }
      }
    }
  }

  DashCard {
    id: weatherCard
    y: clockCard.height + root.gap
    width: root.colA
    height: root.topH - y
    glyph: String.fromCodePoint(0xf034e) // md-map_marker
    title: WeatherState.locationName

    trailing: Text {
      text: String.fromCodePoint(0xf0450) // md-refresh
      color: WeatherState.status === "loading" ? Theme.accent : Theme.textDim
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(15)
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Theme.gapXS
        cursorShape: Qt.PointingHandCursor
        onClicked: WeatherState.refresh()
      }
    }

    Text {
      anchors.centerIn: parent
      visible: !WeatherState.hasData
      text: WeatherState.status === "error" ? "Weather unavailable" : "Loading weather…"
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(12)
    }

    Item {
      anchors.fill: parent
      visible: WeatherState.hasData

      Text {
        id: wxGlyph
        y: Theme.gapXS
        text: WeatherState.hasData ? WeatherState.codeGlyph(WeatherState.current.code, WeatherState.current.isDay) : ""
        color: Theme.accent
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(44)
      }
      Column {
        anchors.left: wxGlyph.right
        anchors.leftMargin: Theme.gapS
        anchors.verticalCenter: wxGlyph.verticalCenter
        Text {
          text: WeatherState.hasData ? WeatherState.fmtTemp(WeatherState.current.temp) : ""
          color: Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(28)
          font.bold: true
        }
        Text {
          text: WeatherState.hasData ? WeatherState.codeLabel(WeatherState.current.code) : ""
          color: Theme.textDim
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(11)
        }
      }
      Column {
        anchors.right: parent.right
        anchors.verticalCenter: wxGlyph.verticalCenter
        visible: WeatherState.upcomingDays.length > 0
        Text {
          text: "↑ " + (WeatherState.upcomingDays.length > 0 ? Math.round(WeatherState.upcomingDays[0].tMax) + "°" : "")
          color: Theme.textDim
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(11)
        }
        Text {
          text: "↓ " + (WeatherState.upcomingDays.length > 0 ? Math.round(WeatherState.upcomingDays[0].tMin) + "°" : "")
          color: Theme.textDim
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(11)
        }
      }

      // The next few hours, every two hours.
      Row {
        id: soon
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: wxGlyph.bottom
        anchors.topMargin: Theme.gapS
        Repeater {
          model: WeatherState.upcomingHours.filter((h, i) => i % 2 === 0).slice(0, 4)
          Column {
            required property var modelData
            required property int index
            width: soon.width / 4
            spacing: Theme.fs(2)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: parent.index === 0 ? "Now" : WeatherState.fmtHour(parent.modelData.time)
              color: Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(10)
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: WeatherState.codeGlyph(parent.modelData.code, WeatherState.isDayAt(parent.modelData.time))
              color: Theme.textDim
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(16)
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Math.round(parent.modelData.temp) + "°"
              color: Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(11)
              font.bold: true
            }
          }
        }
      }

      Grid {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        columns: 2
        spacing: Theme.gapS
        readonly property real cellW: (width - spacing) / 2
        readonly property real cellH: Theme.fs(48)

        Tile {
          width: parent.cellW; height: parent.cellH
          glyph: String.fromCodePoint(0xf050f) // md-thermometer
          label: "Feels"
          value: WeatherState.hasData ? WeatherState.fmtTemp(WeatherState.current.feels) : "--"
        }
        Tile {
          width: parent.cellW; height: parent.cellH
          glyph: String.fromCodePoint(0xf054a) // md-umbrella
          label: "Rain"
          value: WeatherState.upcomingHours.length > 0 ? WeatherState.fmtPercent(WeatherState.upcomingHours[0].precipProb) : "--"
        }
        Tile {
          width: parent.cellW; height: parent.cellH
          glyph: String.fromCodePoint(0xf058e) // md-water_percent
          label: "Humidity"
          value: WeatherState.hasData ? WeatherState.fmtPercent(WeatherState.current.humidity) : "--"
        }
        Tile {
          width: parent.cellW; height: parent.cellH
          glyph: String.fromCodePoint(0xf059d) // md-weather_windy
          label: "Wind"
          value: WeatherState.hasData ? Math.round(WeatherState.current.wind) + " mph" : "--"
        }
      }
    }
  }

  // ===================== column B: calendar + today =====================

  DashCard {
    id: calendarCard
    x: root.colA + root.gap
    width: root.colB
    height: root.topH - todayCard.height - root.gap
    title: Qt.formatDate(new Date(cal.viewYear, cal.viewMonth, 1), "MMMM yyyy")

    trailing: Row {
      spacing: Theme.gapM
      Repeater {
        model: [{ g: 0xf0141, d: -1 }, { g: 0xf0142, d: 1 }] // md-chevron_left / right
        Text {
          required property var modelData
          text: String.fromCodePoint(modelData.g)
          color: Theme.textDim
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(15)
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Theme.gapXS
            cursorShape: Qt.PointingHandCursor
            onClicked: cal.step(parent.modelData.d)
          }
        }
      }
    }

    Item {
      id: cal
      anchors.fill: parent
      property int viewYear: root.today.getFullYear()
      property int viewMonth: root.today.getMonth()
      // Back to this month whenever the dashboard is reopened.
      Connections {
        target: DashboardState
        function onPanelVisibleChanged() {
          cal.viewYear = Qt.binding(() => root.today.getFullYear())
          cal.viewMonth = Qt.binding(() => root.today.getMonth())
        }
      }
      function step(d) {
        const m = new Date(viewYear, viewMonth + d, 1)
        viewYear = m.getFullYear()
        viewMonth = m.getMonth()
      }

      readonly property real weekColW: Theme.fs(26)
      readonly property real cellW: (width - weekColW) / 7
      readonly property real cellH: height / 7

      // Sunday-first rows, so the weekend brackets each week.
      readonly property var days: {
        const first = new Date(viewYear, viewMonth, 1)
        const start = new Date(viewYear, viewMonth, 1 - first.getDay())
        const out = []
        for (var i = 0; i < 42; i++)
          out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i))
        return out
      }

      Repeater {
        model: ["S", "M", "T", "W", "T", "F", "S"]
        Text {
          required property string modelData
          required property int index
          x: cal.weekColW + index * cal.cellW
          width: cal.cellW
          height: cal.cellH
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData
          color: Theme.textMuted
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(11)
          font.bold: true
        }
      }

      Repeater {
        model: 6
        Text {
          required property int index
          y: (index + 1) * cal.cellH
          width: cal.weekColW
          height: cal.cellH
          verticalAlignment: Text.AlignVCenter
          text: root.isoWeek(cal.days[index * 7 + 1])
          color: Theme.textFaint
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(10)
        }
      }

      Repeater {
        model: cal.days
        Item {
          id: cell
          required property var modelData
          required property int index
          readonly property bool inMonth: modelData.getMonth() === cal.viewMonth
          readonly property bool today: modelData.getTime() === root.today.getTime()
          readonly property bool holiday: Holidays.nameOn(modelData) !== ""
          x: cal.weekColW + (index % 7) * cal.cellW
          y: (Math.floor(index / 7) + 1) * cal.cellH
          width: cal.cellW
          height: cal.cellH

          Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) - Theme.fs(4)
            height: width
            radius: width / 2
            visible: cell.today
            color: Theme.accent
          }
          Text {
            anchors.centerIn: parent
            text: cell.modelData.getDate()
            color: cell.today ? Theme.onAccent
                 : cell.holiday && cell.inMonth ? Theme.red
                 : cell.inMonth ? Theme.text : Theme.textFaint
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(12)
            font.bold: cell.today
          }
          Rectangle {
            visible: cell.holiday && cell.inMonth && !cell.today
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.fs(3)
            width: Theme.fs(4)
            height: width
            radius: width / 2
            color: Theme.red
          }
        }
      }
    }
  }

  DashCard {
    id: todayCard
    x: calendarCard.x
    y: root.topH - height
    width: root.colB
    height: Theme.fs(64)

    readonly property var nextHoliday: Holidays.next(root.today)

    Rectangle {
      id: dayBadge
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.fs(34)
      height: width
      radius: Theme.radiusCell
      color: Theme.withAlpha(Theme.accent, 0.18)
      Text {
        anchors.centerIn: parent
        text: root.today.getDate()
        color: Theme.accent
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(15)
        font.bold: true
      }
    }
    Column {
      anchors.left: dayBadge.right
      anchors.leftMargin: Theme.gapS
      anchors.right: countdown.left
      anchors.rightMargin: Theme.gapS
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "Today"
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(13)
        font.bold: true
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: todayCard.nextHoliday ? todayCard.nextHoliday.name : ""
        color: Theme.textDim
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
    }
    Text {
      id: countdown
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: !todayCard.nextHoliday ? ""
          : todayCard.nextHoliday.days === 0 ? "holiday today"
          : todayCard.nextHoliday.days === 1 ? "holiday tomorrow"
          : "holiday in " + todayCard.nextHoliday.days + " days"
      color: Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(11)
      font.bold: true
    }
  }

  // ===================== column C: now playing =====================

  DashCard {
    id: mediaCard
    x: root.width - root.colC
    width: root.colC
    height: root.topH

    Column {
      anchors.centerIn: parent
      visible: !MediaState.hasTrack
      spacing: Theme.gapS
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: MediaState.glyphMusic
        color: Theme.textFaint
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(40)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Nothing playing"
        color: Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
      }
    }

    Column {
      id: nowPlaying
      anchors.left: parent.left
      anchors.right: parent.right
      visible: MediaState.hasTrack
      spacing: Theme.gapS

      Rectangle {
        width: parent.width
        height: width
        radius: Theme.radiusCell
        color: Theme.bgDeep
        clip: true
        Text {
          anchors.centerIn: parent
          visible: art.status !== Image.Ready
          text: MediaState.glyphMusic
          color: Theme.textFaint
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(48)
        }
        Image {
          id: art
          anchors.fill: parent
          source: MediaState.trackArtUrl
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
        }
      }

      Column {
        width: parent.width
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: MediaState.trackTitle
          color: Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(14)
          font.bold: true
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: MediaState.trackArtist
          color: Theme.textDim
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(12)
        }
      }

      Item {
        width: parent.width
        height: Theme.fs(18)
        Text {
          id: elapsed
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: MediaState.formatTime(MediaState.effectivePosition)
          color: Theme.textMuted
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(10)
        }
        Text {
          id: total
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: MediaState.formatTime(MediaState.length)
          color: Theme.textMuted
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(10)
        }
        WaveProgress {
          id: wave
          anchors.left: elapsed.right
          anchors.right: total.left
          anchors.margins: Theme.gapS
          anchors.verticalCenter: parent.verticalCenter
          value: MediaState.progress
          seekable: MediaState.canSeek
          animating: root.live && MediaState.isPlaying
          amplitude: Theme.fs(3)
          wavelength: Theme.fs(16)
          onMoved: fraction => MediaState.seekToFraction(fraction)
        }
        Binding { target: MediaState; property: "dragging"; value: wave.dragging; when: wave.dragging }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.fs(2)
        IconButton {
          bordered: false; size: Theme.fs(32); glyphSize: Theme.fs(15)
          glyph: MediaState.shuffleGlyph; active: MediaState.shuffle
          enabled: MediaState.shuffleSupported
          onClicked: MediaState.toggleShuffle()
        }
        IconButton {
          bordered: false; size: Theme.fs(32); glyphSize: Theme.fs(17)
          glyph: MediaState.glyphPrevious; enabled: MediaState.canPrevious
          onClicked: MediaState.previous()
        }
        IconButton {
          bordered: false; size: Theme.fs(32); glyphSize: Theme.fs(17)
          glyph: MediaState.playGlyph; active: true
          enabled: MediaState.canTogglePlaying
          onClicked: MediaState.togglePlaying()
        }
        IconButton {
          bordered: false; size: Theme.fs(32); glyphSize: Theme.fs(17)
          glyph: MediaState.glyphNext; enabled: MediaState.canNext
          onClicked: MediaState.next()
        }
        IconButton {
          bordered: false; size: Theme.fs(32); glyphSize: Theme.fs(15)
          glyph: MediaState.loopGlyph; active: MediaState.loopActive
          enabled: MediaState.loopSupported
          onClicked: MediaState.cycleLoop()
        }
      }
    }

    // Spectrum in the rest of the card.
    Row {
      visible: MediaState.hasTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: nowPlaying.bottom
      anchors.topMargin: Theme.gapL
      anchors.bottom: parent.bottom
      spacing: Theme.fs(3)
      Repeater {
        model: CavaState.barCount
        Rectangle {
          required property int index
          width: (parent.width - parent.spacing * (CavaState.barCount - 1)) / CavaState.barCount
          height: Math.max(Theme.fs(2), (root.levels[index] || 0) * parent.height)
          anchors.bottom: parent.bottom
          radius: width / 2
          color: Theme.withAlpha(Theme.accent, 0.55)
        }
      }
    }
  }

  // ===================== bottom strip: system rings =====================

  DashCard {
    y: root.height - height
    width: root.width
    height: root.stripH

    Row {
      anchors.fill: parent
      Ring {
        label: "CPU"
        value: SysState.cpuPercent / 100
        ok: SysState.cpuSeeded
        sub: SysState.cpuTempAvailable ? Math.round(SysState.cpuTempF) + "°F" : SysState.loadAvg.toFixed(2) + " load"
      }
      Ring {
        label: "Memory"
        value: SysState.memFraction
        ok: SysState.memTotalBytes > 0
        sub: SysState.fmtGiB(SysState.memUsedBytes)
      }
      Ring {
        label: "GPU"
        value: SysState.gpuPercent / 100
        ok: SysState.gpuAvailable && !SysState.gpuAsleep
        sub: SysState.gpuAsleep ? "asleep" : SysState.gpuTempAvailable ? Math.round(SysState.gpuTempF) + "°F" : "n/a"
      }
      Ring {
        label: "Disk"
        value: SysState.diskFraction
        ok: SysState.diskTotalBytes > 0
        sub: SysState.fmtGiB(SysState.diskTotalBytes - SysState.diskUsedBytes) + " free"
      }
      Item {
        width: parent.width / 5
        height: parent.height
        Row {
          anchors.centerIn: parent
          spacing: Theme.gapS
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fs(44)
            height: width
            radius: width / 2
            color: Theme.withAlpha(Theme.foreground, 0.08)
            Text {
              anchors.centerIn: parent
              text: String.fromCodePoint(0xf0150) // md-clock_outline
              color: Theme.accent
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(20)
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: "Uptime"
              color: Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(12)
              font.bold: true
            }
            Text {
              text: SysState.uptimeSeconds > 0 ? SysState.fmtUptime(SysState.uptimeSeconds) : "--"
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
