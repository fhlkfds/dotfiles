import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import ".."
import "NotificationLogic.js" as Logic

// Elevated card: the theme's surface colour raised off the wallpaper by a soft
// shadow, a small uppercase app label, a round icon badge, and filled/quiet
// action buttons. Spotify track cards keep their own vinyl layout inside the
// same shell.
Item {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string actionsJson: "[]"
  readonly property var actionItems: {
    try {
      const items = JSON.parse(actionsJson)
      return Array.isArray(items) ? items : []
    } catch (e) { return [] }
  }
  property string glyph: ""
  property int urgency: 1
  property real remainingFraction: 1
  property bool expiring: true
  property bool replay: false
  property real timestamp: 0

  readonly property bool hovered: hover.hovered
  readonly property string iconValue: image.length > 0 ? image : appIcon
  readonly property string iconSource: resolveIcon(iconValue)
  readonly property string badgeGlyph: glyph.length > 0 ? glyph : "󰂚"
  readonly property bool vinyl: Logic.isMediaNotification(app, iconSource)
  readonly property var bodyLines: body.split("\n")
  readonly property string trackTitle: vinyl ? bodyLines[0] : ""
  readonly property string trackDetail: vinyl ? bodyLines.slice(1).join(" ") : ""
  readonly property int padX: Theme.fs(NotificationConfig.sidePadding)
  readonly property int padY: Theme.fs(NotificationConfig.multiLinePadding)
  readonly property int radius: Theme.notificationRadius + Theme.fs(4)
  readonly property color accent: urgency === 2 ? Theme.critical : Theme.notificationCountdown
  property real nowMs: Date.now()

  signal closeRequested()
  signal cardClicked()
  signal actionRequested(string identifier)

  function resolveIcon(value) {
    const icon = String(value || "")
    if (!icon) return ""
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    if (icon.charAt(0) === "/") return "file://" + icon
    return Quickshell.iconPath(icon, true)
  }

  implicitWidth: Theme.fs(NotificationConfig.cardWidth)
  implicitHeight: row.implicitHeight + root.padY * 2
                  + (buttons.visible ? buttons.implicitHeight + Theme.fs(10) : 0)
                  + Theme.fs(4)

  // Replayed cards age while they sit on screen.
  Timer {
    interval: 30000
    repeat: true
    running: root.replay
    onTriggered: root.nowMs = Date.now()
  }

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.closeRequested()
      else root.cardClicked()
    }
  }

  // Shadow: MultiEffect pads itself to fit, and the input mask is built from the
  // card geometry alone, so the shadow stays click-through.
  Rectangle {
    id: shadowShape
    anchors.fill: parent
    radius: root.radius
    color: Theme.notificationSurface
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
    id: surface
    anchors.fill: parent
    radius: root.radius
    color: Theme.notificationSurface
    border.width: 1
    border.color: Qt.rgba(Theme.notificationText.r, Theme.notificationText.g,
                          Theme.notificationText.b, 0.08)
  }

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.padX
    anchors.rightMargin: root.padX
    anchors.topMargin: root.padY
    spacing: Theme.fs(NotificationConfig.iconGap)

    NotificationVinyl {
      visible: root.vinyl
      Layout.preferredWidth: visible ? implicitWidth : 0
      Layout.preferredHeight: visible ? implicitHeight : 0
      Layout.alignment: Qt.AlignVCenter
      source: root.iconSource
      sleeveSize: Theme.fs(NotificationConfig.vinylSize)
    }

    // Round badge holding the app icon, a known glyph, or the bell fallback.
    Rectangle {
      visible: !root.vinyl
      Layout.preferredWidth: Theme.fs(NotificationConfig.iconSize)
      Layout.preferredHeight: Theme.fs(NotificationConfig.iconSize)
      Layout.alignment: Qt.AlignTop
      radius: width / 2
      color: Theme.notificationBackground

      Image {
        id: icon
        anchors.centerIn: parent
        width: Math.round(parent.width * 0.6)
        height: width
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // Senders reuse one file for different images; never show a stale copy.
        cache: false
        smooth: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: icon.status !== Image.Ready
        text: root.badgeGlyph
        color: root.accent
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(20)
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Theme.fs(2)

      RowLayout {
        Layout.fillWidth: true
        Layout.rightMargin: Theme.fs(NotificationConfig.closeSize)
        visible: root.app.length > 0 || root.replay
        spacing: Theme.fs(8)

        Text {
          Layout.fillWidth: true
          text: root.app.toUpperCase()
          textFormat: Text.PlainText
          color: root.vinyl ? Theme.notificationCountdown : Theme.notificationClose
          font.family: Theme.uiFamily
          font.pixelSize: Theme.fs(10.5)
          font.weight: Font.Bold
          font.letterSpacing: Theme.fs(1.2)
          elide: Text.ElideRight
          maximumLineCount: 1
        }

        Text {
          visible: root.replay
          text: Logic.ageLabel(root.timestamp, root.nowMs)
          color: Theme.notificationClose
          font.family: Theme.uiFamily
          font.pixelSize: Theme.fs(11)
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.rightMargin: Theme.fs(NotificationConfig.closeSize)
        visible: root.vinyl ? root.trackTitle.length > 0 : root.summary.length > 0
        text: root.vinyl ? root.trackTitle : root.summary
        textFormat: Text.PlainText
        color: Theme.notificationText
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(root.vinyl ? 17 : 14.5)
        font.weight: root.vinyl ? Font.Bold : Font.DemiBold
        wrapMode: root.vinyl ? Text.NoWrap : Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: root.vinyl ? 1 : 2
      }

      Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.vinyl ? root.trackDetail : root.body
        textFormat: Text.PlainText
        color: Theme.notificationBodyText
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(13.5)
        wrapMode: root.vinyl ? Text.NoWrap : Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: root.vinyl ? 1 : 3
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Theme.fs(6)
        visible: root.vinyl && MediaState.hasTrack
        height: Theme.fs(3)
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
          width: parent.width * MediaState.progress
          height: parent.height
          radius: parent.radius
          color: Theme.notificationCountdown
          Behavior on width { NumberAnimation { duration: 250 } }
        }
      }
    }
  }

  // First action is the filled primary; the rest stay quiet on the surface.
  GridLayout {
    id: buttons
    anchors.top: row.bottom
    anchors.topMargin: Theme.fs(10)
    anchors.left: row.left
    anchors.right: row.right
    columnSpacing: Theme.fs(8)
    rowSpacing: Theme.fs(8)
    columns: Math.max(1, Math.min(root.actionItems.length,
      Math.floor((width + columnSpacing) / (Theme.fs(96) + columnSpacing))))
    visible: root.actionItems.length > 0

    Repeater {
      model: root.actionItems
      delegate: Button {
        id: action
        required property var modelData
        required property int index
        readonly property bool primary: index === 0
        objectName: "notificationAction-" + modelData.identifier
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        text: modelData.text
        implicitHeight: Theme.fs(30)
        onClicked: root.actionRequested(modelData.identifier)
        contentItem: Text {
          text: action.text
          textFormat: Text.PlainText
          color: !action.primary ? Theme.notificationText
               : root.urgency === 2 ? Theme.notificationCriticalActionText : Theme.notificationActionText
          font.family: Theme.uiFamily
          font.pixelSize: Theme.fs(13)
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
        background: Rectangle {
          radius: Theme.fs(8)
          color: action.primary ? root.accent : Theme.surfaceAlt
          opacity: action.hovered || action.activeFocus ? 0.85 : 1
        }
      }
    }
  }

  // Countdown: a short inset line along the bottom edge.
  Rectangle {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.padX
    anchors.bottomMargin: Theme.fs(5)
    width: Math.max(0, (parent.width - root.padX * 2) *
                       Math.max(0, Math.min(1, root.remainingFraction)))
    height: Theme.fs(NotificationConfig.countdownHeight)
    radius: height / 2
    visible: root.expiring
    color: root.accent
  }

  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.fs(6)
    anchors.rightMargin: Theme.fs(8)
    width: Theme.fs(NotificationConfig.closeSize)
    height: Theme.fs(NotificationConfig.closeSize)
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: NotificationConfig.closeFadeMs } }

    Text {
      anchors.centerIn: parent
      text: "×"
      color: closeArea.containsMouse ? Theme.notificationText : Theme.notificationClose
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(16)
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }
}
