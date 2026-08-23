import QtQuick

// Weather page: header + current card, hourly strip, 7-day forecast.
// Intrinsic size from tokens; only fields Open-Meteo actually returns are shown.
Item {
  id: root
  implicitWidth: Theme.weatherPageW
  implicitHeight: Theme.weatherPageH

  readonly property int hourCount: 7

  Column {
    x: 0
    y: 0
    spacing: Theme.gapM

    // --- header + current conditions ---
    Row {
      spacing: Theme.gapM

      // header / location
      Card {
        radius: Theme.radiusXL
        implicitWidth: root.implicitWidth - Theme.weatherCardW - Theme.gapM
        implicitHeight: Theme.weatherHeaderH

        Column {
        anchors.left: parent.left
        anchors.top: parent.top
        spacing: 1

        Text {
          text: "Chicago"
          color: Theme.text
          font.pixelSize: Theme.fs(28)
          font.bold: true
        }
        Text {
          text: Qt.formatDateTime(ClockState.zonedDate(), "dddd, MMMM d")
          color: Theme.textDim
          font.pixelSize: Theme.fs(13)
        }
        Item { width: 1; height: Theme.gapM }

        Grid {
          columns: 2
          columnSpacing: Theme.gapXL
          rowSpacing: Theme.gapS

          Text {
            text: "Feels like  " + (WeatherState.hasData
                  ? WeatherState.fmtTemp(WeatherState.current.feels) : "--")
            color: Theme.text; font.pixelSize: Theme.fs(12)
          }
          Text {
            text: "Humidity  " + (WeatherState.hasData
                  ? WeatherState.current.humidity + "%" : "--")
            color: Theme.text; font.pixelSize: Theme.fs(12)
          }
          Text {
            text: "Wind  " + (WeatherState.hasData
                  ? Math.round(WeatherState.current.wind) + " mph" : "--")
            color: Theme.text; font.pixelSize: Theme.fs(12)
          }
          Text {
            text: "Rain today  " + (WeatherState.daily.length > 0
                  ? WeatherState.daily[0].precipMax + "%" : "--")
            color: WeatherState.rainSoon ? Theme.accent : Theme.text
            font.pixelSize: Theme.fs(12)
          }
          Text {
            text: String.fromCodePoint(0xf059c) + "  " + (WeatherState.daily.length > 0
                  ? WeatherState.fmtClock(WeatherState.daily[0].sunrise) : "--")
            font.family: Theme.glyphFamily
            color: Theme.text; font.pixelSize: Theme.fs(12)
          }
          Text {
            text: String.fromCodePoint(0xf059b) + "  " + (WeatherState.daily.length > 0
                  ? WeatherState.fmtClock(WeatherState.daily[0].sunset) : "--")
            font.family: Theme.glyphFamily
            color: Theme.text; font.pixelSize: Theme.fs(12)
          }
        }
        }
      }

      // current conditions -- icon and temperature dominate
      Card {
        radius: Theme.radiusXL
        implicitWidth: Theme.weatherCardW
        implicitHeight: Theme.weatherHeaderH
        unavailable: !WeatherState.hasData
        unavailableText: WeatherState.status === "loading"
                         ? "loading…" : "weather unavailable"

        Item {
          width: Theme.weatherCardW - Theme.gapL * 2
          height: Theme.weatherHeaderH - Theme.gapL * 2

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: WeatherState.hasData
                  ? WeatherState.codeGlyph(WeatherState.current.code,
                                           WeatherState.current.isDay) : ""
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(68)
            color: Theme.text
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: cond.top
            text: WeatherState.hasData
                  ? WeatherState.fmtTemp(WeatherState.current.temp) : "--"
            color: Theme.text
            font.bold: true
            font.pixelSize: Theme.fs(46)
          }
          Text {
            id: cond
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: WeatherState.hasData
                  ? WeatherState.codeLabel(WeatherState.current.code) : ""
            color: Theme.textDim
            font.pixelSize: Theme.fs(16)
          }
        }
      }
    }

    // --- hourly strip ---
    Card {
      title: "NEXT HOURS"
      radius: Theme.radiusXL
      implicitWidth: root.implicitWidth
      implicitHeight: Theme.hourlyCardH

      Row {
        spacing: Theme.gapS

        Repeater {
          model: WeatherState.upcomingHours.slice(0, root.hourCount)

          Rectangle {
            required property var modelData
            required property int index
            width: Theme.hourCardW
            height: Theme.hourCardH
            radius: Theme.radiusM
            color: Theme.bgDeep

            Column {
              anchors.centerIn: parent
              spacing: Theme.gapXS

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: index === 0 ? "NOW" : WeatherState.fmtHour(modelData.time)
                color: index === 0 ? Theme.accent : Theme.textMuted
                font.pixelSize: Theme.fs(10)
                font.bold: index === 0
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: WeatherState.codeGlyph(modelData.code,
                                             WeatherState.isDayAt(modelData.time))
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(22)
                color: Theme.text
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(modelData.temp) + "°"
                color: Theme.text
                font.pixelSize: Theme.fs(14)
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.precipProb + "%"
                color: modelData.precipProb >= WeatherState.rainThreshold
                       ? Theme.accent : Theme.textMuted
                font.pixelSize: Theme.fs(10)
              }
            }
          }
        }
      }
    }

    // --- 7 day ---
    Card {
      title: "7 DAY"
      radius: Theme.radiusXL
      implicitWidth: root.implicitWidth
      implicitHeight: Theme.forecastCardH

      Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Theme.gapXS

      Repeater {
        model: WeatherState.daily

        Row {
          required property var modelData
          spacing: Theme.gapM
          height: Theme.fs(24)

          Text {
            width: Theme.fs(44)
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherState.fmtDay(modelData.date)
            color: Theme.text; font.pixelSize: Theme.fs(12)
          }
          Text {
            width: Theme.fs(24)
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherState.codeGlyph(modelData.code, true)
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(16); color: Theme.text
          }
          Text {
            width: Theme.fs(40)
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(modelData.tMin) + "°"
            color: Theme.textMuted; font.pixelSize: Theme.fs(12)
          }
          // Range bar between the day's low and high.
          Rectangle {
            width: Theme.fs(300)
            height: Theme.fs(5)
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.bgDeep

            Rectangle {
              readonly property real lo: 30
              readonly property real hi: 110
              x: Math.max(0, Math.min(1, (modelData.tMin - lo) / (hi - lo))) * parent.width
              width: Math.max(Theme.fs(4),
                     Math.min(1, (modelData.tMax - lo) / (hi - lo)) * parent.width - x)
              height: parent.height
              radius: height / 2
              color: Theme.accent
            }
          }
          Text {
            width: Theme.fs(40)
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(modelData.tMax) + "°"
            color: Theme.text; font.pixelSize: Theme.fs(12)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.precipMax + "%"
            color: modelData.precipMax >= WeatherState.rainThreshold
                   ? Theme.accent : Theme.textMuted
            font.pixelSize: Theme.fs(11)
          }
        }
      }
      }
    }
  }
}
