import QtQuick

// The bar's centre: the clock pinned to the screen centre, the indicator row
// to its left, and the capsule drawn behind both. The capsule never grows or
// pops out; track changes and notifications leave it alone. Bar.qml passes
// the indicators and the neighbouring islands' edges, which is what lets
// BarCenterSmoke load this headless.
Item {
  id: centerGroup

  property real barScale: 1.0
  // Right edge of the left island and left edge of the right island group.
  property real leftEdge: 0
  property real rightEdge: width
  default property alias indicators: leadingRow.data
  readonly property alias clock: clockLabel
  readonly property alias capsule: centerIsland
  signal clockClicked()

  // Distance from the clock to each side row.
  readonly property int rowMargin: Theme.fs(8 * barScale)

  // Scaling the content down keeps the islands apart on narrow bars;
  // this shift is the backstop when scaling is not enough.
  //
  // Every term is a width or the x of something the offset does not
  // move. Deriving any of it from leadingRow.x or clockLabel.x would
  // feed the offset back into itself and cycle the binding.
  readonly property real clockBase: (width - clockLabel.width) / 2
  readonly property real leadingNeed:
    rowMargin + leadingRow.width + Theme.barIslandPadding
  readonly property real trailingNeed:
    rowMargin + Theme.barIslandPadding
  readonly property real minShift:
    leftEdge + Theme.barIslandGap - clockBase + leadingNeed
  readonly property real maxShift:
    rightEdge - Theme.barIslandGap - clockBase - clockLabel.width - trailingNeed
  // When even the clamp cannot satisfy both sides there is genuinely no
  // room, so split the shortfall rather than dumping all of it on one
  // neighbour.
  readonly property real collisionShift:
    minShift > maxShift ? (minShift + maxShift) / 2
                        : Math.min(Math.max(0, minShift), maxShift)

  // Drawn from the indicator row and clock rather than wrapping them in a
  // BarIsland, because the clock has to stay pinned to the screen centre.
  // A content-sized capsule would centre itself instead, and the time
  // would drift sideways every time a mode pill appeared.
  Rectangle {
    id: centerIsland
    objectName: "centerCapsule"
    anchors.verticalCenter: parent.verticalCenter
    x: leadingRow.x - Theme.barIslandPadding
    width: clockLabel.x + clockLabel.width + centerGroup.rowMargin
           + Theme.barIslandPadding - x
    height: Theme.barIslandHeight
    radius: height / 2
    color: Theme.bgDeep
  }

  // Time over date, then the current conditions. One item, so the
  // centring and collision maths above treat the whole block as the clock.
  Row {
    id: clockLabel
    objectName: "centerClock"
    anchors.centerIn: parent
    // Zero whenever the bar is wide enough, which is every landscape
    // monitor. The clock only leaves true centre to avoid a collision.
    anchors.horizontalCenterOffset: centerGroup.collisionShift
    spacing: Theme.fs(14 * centerGroup.barScale)

    Column {
      anchors.verticalCenter: parent.verticalCenter

      Text {
        text: Qt.formatDateTime(ClockState.zonedDate(), "hh:mm:ss AP")
        color: Theme.green
        font.family: Theme.glyphFamily
        font.bold: true
        font.pixelSize: Theme.fs(12 * centerGroup.barScale)
      }

      Text {
        text: Qt.formatDateTime(ClockState.zonedDate(), "dddd, MMMM d")
        color: Theme.textDim
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(8 * centerGroup.barScale)
      }
    }

    // Hidden until the first fetch lands, so the clock never shows a
    // placeholder temperature.
    Row {
      anchors.verticalCenter: parent.verticalCenter
      visible: WeatherState.hasData
      spacing: Theme.fs(6 * centerGroup.barScale)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: WeatherState.hasData
              ? WeatherState.codeGlyph(WeatherState.current.code,
                                       WeatherState.current.isDay) : ""
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(16 * centerGroup.barScale)
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: WeatherState.hasData
              ? WeatherState.current.temp.toFixed(1) + "°F" : ""
        color: Theme.text
        font.family: Theme.glyphFamily
        font.bold: true
        font.pixelSize: Theme.fs(13 * centerGroup.barScale)
      }
    }
  }

  // The time and the weather beside it are one target: either opens
  // the dashboard (overview, media, system, weather).
  MouseArea {
    anchors.fill: clockLabel
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: centerGroup.clockClicked()
  }

  Row {
    id: leadingRow
    anchors.right: clockLabel.left
    anchors.rightMargin: centerGroup.rowMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.fs(3 * centerGroup.barScale)
  }
}
