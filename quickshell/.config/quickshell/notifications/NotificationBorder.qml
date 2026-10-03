import QtQuick
import QtQuick.Effects
import ".."

// Elevated shell shared by every card: the theme's notification surface raised
// off the wallpaper by a soft shadow. The former per-side gradient border is
// gone; a `borderWidths` key left in config.json is accepted and ignored.
Item {
  id: root
  default property alias contentData: content.data

  property color surfaceColor: Theme.notificationSurface
  property int cornerRadius: Theme.notificationRadius + Theme.fs(4)

  // MultiEffect pads itself to fit the blur, but the item keeps the card's
  // geometry, so the input mask built from it leaves the shadow click-through.
  Rectangle {
    id: shadowShape
    anchors.fill: parent
    radius: root.cornerRadius
    color: root.surfaceColor
    visible: false
  }

  MultiEffect {
    anchors.fill: shadowShape
    source: shadowShape
    shadowEnabled: true
    shadowColor: Theme.notificationShadow
    shadowOpacity: Theme.shadowOpacity
    shadowBlur: 1.0
    shadowVerticalOffset: Theme.fs(6)
    shadowScale: 1.0
  }

  Rectangle {
    anchors.fill: parent
    radius: root.cornerRadius
    color: root.surfaceColor
    border.width: 1
    border.color: Qt.rgba(Theme.notificationText.r, Theme.notificationText.g,
                          Theme.notificationText.b, 0.08)
  }

  Item {
    id: content
    anchors.fill: parent
  }
}
