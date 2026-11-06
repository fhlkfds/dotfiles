import QtQuick
import QtQuick.Layouts

// The pill itself. Takes its state as a property so the smoke can load it
// with a fake; OsdPopup passes the OsdState singleton.
Rectangle {
  id: pill
  required property var osd

  implicitWidth: content.implicitWidth + Theme.gapL * 2
  implicitHeight: content.implicitHeight + Theme.gapM * 2
  radius: height / 2
  color: Theme.background
  border.width: Math.max(1, Theme.borderWidth)
  border.color: Theme.borderAccent
  opacity: osd.visible ? Theme.surfaceOpacity : 0
  Behavior on opacity {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  readonly property real fill: osd.muted ? 0 : Math.min(1, osd.level / 100)

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: Theme.gapM

    Text {
      text: pill.osd.glyph
      color: pill.osd.muted ? Theme.textMuted : Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(22)
    }

    Rectangle {
      Layout.preferredWidth: Theme.fs(160)
      Layout.preferredHeight: Math.max(Theme.fs(6), 2)
      radius: height / 2
      color: Theme.surfaceAlt

      Rectangle {
        width: parent.width * pill.fill
        height: parent.height
        radius: parent.radius
        color: Theme.accent
        Behavior on width {
          NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      Layout.preferredWidth: Theme.fs(52)
      horizontalAlignment: Text.AlignRight
      text: pill.osd.text
      color: Theme.foregroundBright
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(14)
      font.weight: Font.DemiBold
    }
  }
}
