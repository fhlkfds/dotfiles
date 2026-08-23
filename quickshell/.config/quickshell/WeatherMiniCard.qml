import QtQuick

// Dashboard weather summary. Current condition and temperature dominate.
Card {
  id: root
  implicitWidth: Theme.weatherCardW
  implicitHeight: Theme.weatherCardH
  radius: Theme.radiusXL
  // A failed fetch is a transient condition, so it shows an unavailable card
  // rather than vanishing and reflowing the page.
  unavailable: !WeatherState.hasData
  unavailableText: WeatherState.status === "loading" ? "loading…" : "weather unavailable"

  Item {
    anchors.fill: parent
    anchors.margins: Theme.gapL
    visible: WeatherState.hasData

    Text {
      id: city
      anchors.top: parent.top
      anchors.left: parent.left
      text: "Chicago"
      color: Theme.textDim
      font.pixelSize: Theme.fs(14)
    }

    Text {
      anchors.top: parent.top
      anchors.right: parent.right
      text: WeatherState.hasData
            ? WeatherState.codeGlyph(WeatherState.current.code,
                                     WeatherState.current.isDay) : ""
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(46)
      color: Theme.text
    }

    Text {
      id: temp
      anchors.left: parent.left
      anchors.top: city.bottom
      anchors.topMargin: Theme.gapXS
      text: WeatherState.hasData ? Math.round(WeatherState.current.temp) + "°" : "--"
      color: Theme.text
      font.bold: true
      font.pixelSize: Theme.fs(36)
    }

    Text {
      anchors.left: parent.left
      anchors.top: temp.bottom
      anchors.topMargin: -Theme.gapXS
      text: WeatherState.hasData
            ? WeatherState.codeLabel(WeatherState.current.code) : ""
      color: Theme.textDim
      font.pixelSize: Theme.fs(13)
      elide: Text.ElideRight
      width: parent.width
    }

    Row {
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      spacing: Theme.gapM

      Text {
        text: WeatherState.daily.length > 0
              ? "H " + Math.round(WeatherState.daily[0].tMax) + "°  L "
                + Math.round(WeatherState.daily[0].tMin) + "°" : ""
        color: Theme.textMuted
        font.pixelSize: Theme.fs(11)
      }
      Text {
        text: WeatherState.daily.length > 0
              ? "Rain " + WeatherState.daily[0].precipMax + "%" : ""
        color: WeatherState.rainSoon ? Theme.accent : Theme.textMuted
        font.pixelSize: Theme.fs(11)
      }
    }
  }
}
