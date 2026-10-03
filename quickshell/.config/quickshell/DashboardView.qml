import QtQuick

// Body of DashboardPanel: the tab strip and the four pages. Split from the
// window so it can be rendered on its own.
//
// All four pages are instantiated up front and kept; only the active one is
// visible. `shown` is false while the window is unmapped, and every page uses
// `live` to stop its animations and live-data bindings then, so a closed
// dashboard does no per-frame work.
Rectangle {
  id: root
  property bool shown: true

  // Fixed design size, shared by every page.
  readonly property int pageW: Theme.fs(768)
  readonly property int pageH: Theme.fs(560)
  readonly property int pad: Theme.gapL
  readonly property int tabH: Theme.fs(44)

  implicitWidth: pageW + pad * 2
  implicitHeight: pad + tabH + Theme.gapM + pageH + pad

  color: Theme.bg
  radius: Theme.radiusM
  border.width: Theme.borderWidth
  border.color: Theme.hairline
  focus: true

  readonly property var tabs: [
    { key: "overview", label: "Overview", glyph: String.fromCodePoint(0xf056e) }, // md-view_dashboard
    { key: "media",    label: "Media",    glyph: String.fromCodePoint(0xf075a) }, // md-music
    { key: "system",   label: "System",   glyph: String.fromCodePoint(0xf061a) }, // md-chip
    { key: "weather",  label: "Weather",  glyph: String.fromCodePoint(0xf0595) }  // md-weather_partly_cloudy
  ]

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape)
      DashboardState.panelVisible = false
    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
      DashboardState.stepTab(-1)
    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
      DashboardState.stepTab(1)
    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4)
      DashboardState.activeTab = root.tabs[event.key - Qt.Key_1].key
    else
      return
    event.accepted = true
  }

  // --- tabs ------------------------------------------------------------------

  Item {
    id: tabStrip
    x: root.pad
    y: root.pad
    width: root.pageW
    height: root.tabH
    readonly property real tabW: width / root.tabs.length

    Row {
      anchors.fill: parent

      Repeater {
        model: root.tabs

        Item {
          id: tab
          required property var modelData
          readonly property bool current: DashboardState.activeTab === modelData.key
          width: tabStrip.tabW
          height: tabStrip.height

          Row {
            id: tabLabel
            anchors.centerIn: parent
            spacing: Theme.gapS

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: tab.modelData.glyph
              color: tab.current ? Theme.accent : Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(16)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: tab.modelData.label
              color: tab.current ? Theme.text : Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(13)
              font.bold: tab.current
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // On press, not release: the page is already there when the
            // button comes back up.
            onPressed: DashboardState.activeTab = tab.modelData.key
          }
        }
      }
    }

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: Theme.hairline
    }

    // Only the underline moves; the page itself switches instantly.
    Rectangle {
      readonly property int index: Math.max(0, DashboardState.tabs.indexOf(DashboardState.activeTab))
      anchors.bottom: parent.bottom
      width: tabStrip.tabW * 0.42
      height: Theme.fs(3)
      radius: height / 2
      color: Theme.accent
      x: tabStrip.tabW * index + (tabStrip.tabW - width) / 2
      Behavior on x {
        enabled: root.shown
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: wheel => DashboardState.stepTab(wheel.angleDelta.y > 0 ? -1 : 1)
    }
  }

  // --- pages -----------------------------------------------------------------

  // Scrolls only when the window had to be clamped to a short screen.
  Flickable {
    anchors.fill: parent
    anchors.topMargin: root.pad + root.tabH + Theme.gapM
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    anchors.bottomMargin: root.pad
    clip: true
    contentWidth: root.pageW
    contentHeight: root.pageH
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds

    DashOverview {
      width: root.pageW; height: root.pageH
      visible: DashboardState.activeTab === "overview"
      live: root.shown && visible
    }
    DashMedia {
      width: root.pageW; height: root.pageH
      visible: DashboardState.activeTab === "media"
      live: root.shown && visible
    }
    DashSystem {
      width: root.pageW; height: root.pageH
      visible: DashboardState.activeTab === "system"
      live: root.shown && visible
    }
    DashWeather {
      width: root.pageW; height: root.pageH
      visible: DashboardState.activeTab === "weather"
      live: root.shown && visible
    }
  }
}
