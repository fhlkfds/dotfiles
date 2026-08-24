import QtQuick
import QtQuick.Layouts

Rectangle {
  id: card

  implicitWidth: content.implicitWidth + Theme.gapL * 2
  implicitHeight: content.implicitHeight + Theme.gapM * 2
  radius: Theme.radiusM
  color: Theme.background
  border.width: Math.max(1, Theme.borderWidth)
  border.color: Theme.borderAccent
  opacity: Theme.surfaceOpacity

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: Theme.gapM

    Text {
      text: String.fromCodePoint(0xf01da) // md-download
      color: Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(22)
    }

    Rectangle {
      Layout.preferredWidth: Theme.fs(142)
      Layout.preferredHeight: Math.max(Theme.fs(6), 2)
      radius: height / 2
      color: Theme.surfaceAlt

      Rectangle {
        width: parent.width * VideoDownloadState.percent / 100
        height: parent.height
        radius: parent.radius
        color: Theme.accent
        Behavior on width {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      Layout.preferredWidth: Theme.fs(42)
      horizontalAlignment: Text.AlignRight
      text: VideoDownloadState.percent + "%"
      color: Theme.foregroundBright
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(14)
      font.weight: Font.DemiBold
    }
  }
}
