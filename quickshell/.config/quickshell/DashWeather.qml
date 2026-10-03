import QtQuick

// Dashboard weather page: current conditions, the next 24 hours as a
// temperature curve, and the week's ranges. Everything comes from WeatherState
// (Open-Meteo); the dashboard opening asks it for a refresh only when its
// 15-minute cache has expired.
Item {
  id: root
  property bool live: false

  readonly property int gap: Theme.gapM
  readonly property bool ready: WeatherState.hasData

  // Every second hour from now, 12 of them: the next 24 hours.
  readonly property var hours: {
    const all = WeatherState.hourly
    const nowIso = Qt.formatDateTime(new Date(), "yyyy-MM-ddThh:00")
    var i = 0
    while (i < all.length && all[i].time < nowIso)
      i++
    const out = []
    for (var k = i; k < all.length && out.length < 12; k += 2)
      out.push(all[k])
    return out
  }
  readonly property var week: WeatherState.daily.slice(0, 7)
  readonly property real weekMin: week.reduce((m, d) => Math.min(m, d.tMin), Infinity)
  readonly property real weekMax: week.reduce((m, d) => Math.max(m, d.tMax), -Infinity)
  function weekFrac(t) {
    return weekMax > weekMin ? Math.max(0, Math.min(1, (t - weekMin) / (weekMax - weekMin))) : 0.5
  }

  component Tile: Rectangle {
    id: tile
    property string glyph: ""
    property string label: ""
    property string value: ""
    property color glyphColor: Theme.accent
    radius: Theme.radiusCell
    color: Theme.withAlpha(Theme.foreground, 0.05)
    Column {
      anchors.left: parent.left
      anchors.leftMargin: Theme.gapS
      anchors.verticalCenter: parent.verticalCenter
      Row {
        spacing: Theme.gapXS
        Text {
          text: tile.glyph
          color: tile.glyphColor
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(11)
        }
        Text {
          text: tile.label
          color: Theme.textMuted
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(10)
        }
      }
      Text {
        text: tile.value
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(13)
        font.bold: true
      }
    }
  }

  // ===================== current conditions =====================

  DashCard {
    id: nowCard
    width: parent.width
    height: Theme.fs(130)
    glyph: String.fromCodePoint(0xf034e) // md-map_marker
    title: WeatherState.locationName

    trailing: Row {
      spacing: Theme.gapM
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: WeatherState.lastFetchMs > 0
        text: WeatherState.status === "error" ? "Update failed"
              : "Updated " + Qt.formatTime(new Date(WeatherState.lastFetchMs), "h:mm AP")
        color: WeatherState.status === "error" ? Theme.error : Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
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
    }

    Text {
      anchors.centerIn: parent
      visible: !root.ready
      text: WeatherState.status === "error" ? (WeatherState.errorText || "Weather unavailable") : "Loading weather…"
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(12)
    }

    Row {
      visible: root.ready
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.gapS
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.ready ? WeatherState.codeGlyph(WeatherState.current.code, WeatherState.current.isDay) : ""
        color: Theme.accent
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(50)
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: root.ready ? WeatherState.fmtTemp(WeatherState.current.temp) : ""
          color: Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(30)
          font.bold: true
        }
        Text {
          text: root.ready ? WeatherState.codeLabel(WeatherState.current.code)
                             + " · feels " + WeatherState.fmtTemp(WeatherState.current.feels) : ""
          color: Theme.textDim
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(11)
        }
        Text {
          visible: root.week.length > 0
          text: root.week.length > 0
                ? "↑ " + Math.round(root.week[0].tMax) + "°   ↓ " + Math.round(root.week[0].tMin) + "°" : ""
          color: Theme.textMuted
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(11)
        }
      }
    }

    Grid {
      visible: root.ready
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Theme.fs(468)
      columns: 3
      spacing: Theme.gapS
      readonly property real cellW: (width - spacing * 2) / 3
      readonly property real cellH: (height - spacing) / 2

      Tile {
        width: parent.cellW; height: parent.cellH
        glyph: String.fromCodePoint(0xf058e) // md-water_percent
        label: "Humidity"
        value: root.ready ? WeatherState.current.humidity + "%" : "--"
      }
      Tile {
        width: parent.cellW; height: parent.cellH
        glyph: String.fromCodePoint(0xf059d) // md-weather_windy
        label: "Wind"
        value: root.ready ? Math.round(WeatherState.current.wind) + " mph" : "--"
      }
      Tile {
        width: parent.cellW; height: parent.cellH
        glyph: String.fromCodePoint(0xf054a) // md-umbrella
        label: "Rain"
        value: root.hours.length > 0 ? root.hours[0].precipProb + "%" : "--"
      }
      Tile {
        width: parent.cellW; height: parent.cellH
        glyph: String.fromCodePoint(0xf05a8) // md-white_balance_sunny
        glyphColor: Theme.yellow
        label: "UV"
        value: root.ready && WeatherState.current.uv !== undefined
               ? Math.round(WeatherState.current.uv) + " " + WeatherState.uvLabel(WeatherState.current.uv) : "--"
      }
      Tile {
        width: parent.cellW; height: parent.cellH
        glyph: String.fromCodePoint(0xf059c) // md-weather_sunset_up
        glyphColor: Theme.yellow
        label: "Sunrise"
        value: root.week.length > 0 ? WeatherState.fmtClock(root.week[0].sunrise) : "--"
      }
      Tile {
        width: parent.cellW; height: parent.cellH
        glyph: String.fromCodePoint(0xf059b) // md-weather_sunset_down
        glyphColor: Theme.yellow
        label: "Sunset"
        value: root.week.length > 0 ? WeatherState.fmtClock(root.week[0].sunset) : "--"
      }
    }
  }

  // ===================== next 24 hours =====================

  DashCard {
    id: hourlyCard
    y: nowCard.height + root.gap
    width: parent.width
    height: Theme.fs(200)
    glyph: String.fromCodePoint(0xf0150) // md-clock_outline
    title: "Next 24 hours"

    Item {
      id: strip
      anchors.fill: parent
      visible: root.hours.length > 1
      readonly property real colW: width / 12
      readonly property real labelH: Theme.fs(14)
      readonly property real glyphH: Theme.fs(22)
      readonly property real pillsH: Theme.fs(16)
      // The curve's band, between the glyph row and the rain pills, leaving
      // room above each point for its label.
      readonly property real chartTop: labelH + glyphH + Theme.fs(22)
      readonly property real chartBottom: height - pillsH - Theme.fs(8)
      readonly property real tMin: root.hours.reduce((m, h) => Math.min(m, h.temp), Infinity)
      readonly property real tMax: root.hours.reduce((m, h) => Math.max(m, h.temp), -Infinity)
      function pointY(t) {
        const f = tMax > tMin ? (t - tMin) / (tMax - tMin) : 0.5
        return chartBottom - f * (chartBottom - chartTop)
      }

      Canvas {
        id: curve
        anchors.fill: parent
        property var pts: root.hours.map((h, i) => ({ x: strip.colW * (i + 0.5), y: strip.pointY(h.temp) }))
        property color line: Theme.accent
        onPtsChanged: requestPaint()
        onLineChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
          const ctx = getContext("2d")
          ctx.reset()
          if (pts.length < 2)
            return
          // Smooth through the points with midpoint quadratics.
          ctx.beginPath()
          ctx.moveTo(pts[0].x, pts[0].y)
          for (var i = 1; i < pts.length; i++) {
            const mx = (pts[i - 1].x + pts[i].x) / 2
            const my = (pts[i - 1].y + pts[i].y) / 2
            ctx.quadraticCurveTo(pts[i - 1].x, pts[i - 1].y, mx, my)
          }
          ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y)
          ctx.strokeStyle = line
          ctx.lineWidth = Theme.fs(2)
          ctx.stroke()

          ctx.lineTo(pts[pts.length - 1].x, strip.chartBottom)
          ctx.lineTo(pts[0].x, strip.chartBottom)
          ctx.closePath()
          const g = ctx.createLinearGradient(0, strip.chartTop, 0, strip.chartBottom)
          g.addColorStop(0, Qt.rgba(line.r, line.g, line.b, 0.28))
          g.addColorStop(1, Qt.rgba(line.r, line.g, line.b, 0))
          ctx.fillStyle = g
          ctx.fill()

          ctx.fillStyle = line
          for (var j = 0; j < pts.length; j++) {
            ctx.beginPath()
            ctx.arc(pts[j].x, pts[j].y, Theme.fs(3), 0, Math.PI * 2)
            ctx.fill()
          }
        }
      }

      Repeater {
        model: root.hours
        Item {
          required property var modelData
          required property int index
          x: strip.colW * index
          width: strip.colW
          height: strip.height

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: parent.index === 0 ? "Now" : WeatherState.fmtHour(parent.modelData.time)
            color: parent.index === 0 ? Theme.text : Theme.textMuted
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(10)
            font.bold: parent.index === 0
          }
          Text {
            y: strip.labelH
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: WeatherState.codeGlyph(parent.modelData.code, WeatherState.isDayAt(parent.modelData.time))
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(17)
          }
          Text {
            y: strip.pointY(parent.modelData.temp) - Theme.fs(20)
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Math.round(parent.modelData.temp) + "°"
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(11)
            font.bold: true
          }
          // Precipitation chance, as a pill that fills up.
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: Theme.fs(6)
            height: strip.pillsH
            radius: width / 2
            color: Theme.withAlpha(Theme.foreground, 0.08)
            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: Math.max(width, parent.height * parent.parent.modelData.precipProb / 100)
              radius: width / 2
              visible: parent.parent.modelData.precipProb > 0
              color: parent.parent.modelData.precipProb >= WeatherState.rainThreshold
                     ? Theme.accent : Theme.withAlpha(Theme.accent, 0.45)
            }
          }
        }
      }
    }
  }

  // ===================== 7 days =====================

  DashCard {
    y: hourlyCard.y + hourlyCard.height + root.gap
    width: parent.width
    height: parent.height - y
    glyph: String.fromCodePoint(0xf00ed) // md-calendar
    title: "7 days"

    Column {
      anchors.fill: parent
      Repeater {
        model: root.week
        Item {
          id: day
          required property var modelData
          required property int index
          width: parent.width
          height: parent.height / 7

          Row {
            id: lead
            anchors.verticalCenter: parent.verticalCenter
            Text {
              width: Theme.fs(64)
              text: day.index === 0 ? "Today" : WeatherState.fmtDay(day.modelData.date)
              color: Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(12)
              font.bold: day.index === 0
            }
            Text {
              width: Theme.fs(30)
              text: WeatherState.codeGlyph(day.modelData.code, true)
              color: Theme.textDim
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(15)
            }
            Text {
              width: Theme.fs(62)
              text: String.fromCodePoint(0xf058c) + " " + day.modelData.precipMax + "%" // md-water
              color: day.modelData.precipMax >= WeatherState.rainThreshold ? Theme.accent : Theme.textFaint
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(11)
            }
            Text {
              width: Theme.fs(40)
              horizontalAlignment: Text.AlignRight
              text: Math.round(day.modelData.tMin) + "°"
              color: Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(12)
            }
          }

          // The day's low-to-high span, placed on the week's overall range.
          Rectangle {
            id: track
            anchors.left: lead.right
            anchors.leftMargin: Theme.gapM
            anchors.right: high.left
            anchors.rightMargin: Theme.gapM
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.fs(5)
            radius: height / 2
            color: Theme.withAlpha(Theme.foreground, 0.08)

            Rectangle {
              x: root.weekFrac(day.modelData.tMin) * track.width
              width: Math.max(height, root.weekFrac(day.modelData.tMax) * track.width - x)
              height: parent.height
              radius: height / 2
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.blue }
                GradientStop { position: 1; color: Theme.yellow }
              }
            }
            // Where today's temperature sits right now.
            Rectangle {
              visible: day.index === 0 && root.ready
              x: root.weekFrac(root.ready ? WeatherState.current.temp : 0) * track.width - width / 2
              anchors.verticalCenter: parent.verticalCenter
              width: Theme.fs(11)
              height: width
              radius: width / 2
              color: Theme.text
              border.width: Theme.fs(2)
              border.color: Theme.bg
            }
          }

          Text {
            id: high
            anchors.right: uv.left
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fs(40)
            text: Math.round(day.modelData.tMax) + "°"
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(12)
          }
          Text {
            id: uv
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fs(40)
            horizontalAlignment: Text.AlignRight
            visible: day.modelData.uvMax !== null && day.modelData.uvMax !== undefined
            text: String.fromCodePoint(0xf05a8) + " " + Math.round(day.modelData.uvMax) // md-white_balance_sunny
            color: Theme.yellow
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(11)
          }
        }
      }
    }
  }
}
