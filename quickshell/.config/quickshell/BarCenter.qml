import QtQuick
import "island/IslandLogic.js" as IslandLogic

// The bar's centre: the clock pinned to the screen centre, the indicator row
// to its left, and the capsule drawn behind both. A glance from IslandState
// widens the capsule about the clock and shows in the clock's place; the clock
// itself never moves. Bar.qml passes the indicators and the neighbouring
// islands' edges, which is what lets IslandSmoke load this headless.
Item {
  id: centerGroup

  property real barScale: 1.0
  property string screenName: ""
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
  // feed the offset back into itself and cycle the binding. The glance
  // capsule is likewise left out, so the clock cannot drift when it grows.
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

  readonly property bool glancing: IslandState.current !== null
  // Kept after the glance ends so its text stays put while the capsule folds.
  property var shownGlance: null
  readonly property real clockCentre: clockLabel.x + clockLabel.width / 2
  readonly property real glanceMinX: leftEdge + Theme.barIslandGap
  readonly property real glanceMaxX: rightEdge - Theme.barIslandGap
  readonly property real restX: leadingRow.x - Theme.barIslandPadding
  readonly property real restWidth: clockLabel.x + clockLabel.width + rowMargin
                                    + Theme.barIslandPadding - restX
  readonly property var span: IslandLogic.capsuleSpan(
    { x: restX, width: restWidth }, clockCentre,
    glancing ? glance.width + Theme.barIslandPadding * 2 : 0,
    glanceMinX, glanceMaxX)

  Connections {
    target: IslandState
    function onCurrentChanged() {
      if (IslandState.current) centerGroup.shownGlance = IslandState.current
    }
  }

  // Drawn from the indicator row and clock rather than wrapping them in a
  // BarIsland, because the clock has to stay pinned to the screen centre.
  // A content-sized capsule would centre itself instead, and the time
  // would drift sideways every time a mode pill appeared.
  Rectangle {
    id: centerIsland
    objectName: "islandCapsule"
    anchors.verticalCenter: parent.verticalCenter
    x: centerGroup.span.x
    width: centerGroup.span.width
    height: centerGroup.glancing ? Theme.barIslandHeight + Theme.barGap
                                 : Theme.barIslandHeight
    radius: height / 2
    color: Theme.bgDeep

    Behavior on x { NumberAnimation { duration: IslandState.animationMs; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: IslandState.animationMs; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: IslandState.animationMs; easing.type: Easing.OutCubic } }

    HoverHandler {
      enabled: centerGroup.glancing
      onHoveredChanged: IslandState.hover(centerGroup.screenName, hovered)
    }
    TapHandler {
      enabled: centerGroup.glancing
      onTapped: IslandState.hover(centerGroup.screenName, true)
    }
  }

  // Time over date, then the current conditions. One item, so the
  // centring and collision maths above treat the whole block as the clock.
  Row {
    id: clockLabel
    objectName: "islandClock"
    anchors.centerIn: parent
    // Zero whenever the bar is wide enough, which is every landscape
    // monitor. The clock only leaves true centre to avoid a collision.
    anchors.horizontalCenterOffset: centerGroup.collisionShift
    spacing: Theme.fs(14 * centerGroup.barScale)
    opacity: centerGroup.glancing ? 0 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: IslandState.animationMs } }

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
    enabled: !centerGroup.glancing
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
    opacity: clockLabel.opacity
    visible: opacity > 0
  }

  IslandGlance {
    id: glance
    objectName: "islandGlance"
    anchors.horizontalCenter: clockLabel.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    glance: centerGroup.shownGlance
    barScale: centerGroup.barScale
    maxWidth: Math.max(0, Math.min(
      Theme.fs(IslandState.glanceMaxWidth * centerGroup.barScale),
      2 * Math.min(centerGroup.clockCentre - centerGroup.glanceMinX,
                   centerGroup.glanceMaxX - centerGroup.clockCentre)
      - Theme.barIslandPadding * 2))
    opacity: centerGroup.glancing ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: IslandState.animationMs } }
  }
}
