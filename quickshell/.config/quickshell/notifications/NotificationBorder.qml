import QtQuick
import ".."

Item {
  id: root
  default property alias contentData: content.data

  property color backgroundColor: Theme.notificationBackground
  property color borderColor1: Theme.notificationBorder1
  property color borderColor2: Theme.notificationBorder2
  property real borderAlpha: Theme.notificationBorderAlpha
  property real borderAngle: Theme.notificationBorderAngle
  property int cornerRadius: Theme.notificationRadius
  property var widths: {
    const configured = NotificationConfig.borderWidths
    const fallback = Theme.fs(2)
    return configured.length === 4
      ? configured.map(function(value) { return Theme.fs(value) })
      : [fallback, fallback, fallback, fallback]
  }

  readonly property int topWidth: Math.max(0, widths[0] || 0)
  readonly property int rightWidth: Math.max(0, widths[1] || 0)
  readonly property int bottomWidth: Math.max(0, widths[2] || 0)
  readonly property int leftWidth: Math.max(0, widths[3] || 0)

  Rectangle {
    anchors.fill: parent
    radius: root.cornerRadius
    gradient: Gradient {
      orientation: root.borderAngle >= 45 && root.borderAngle <= 135
                   ? Gradient.Horizontal : Gradient.Vertical
      GradientStop {
        position: 0
        color: Qt.rgba(root.borderColor1.r, root.borderColor1.g,
                       root.borderColor1.b, root.borderAlpha)
      }
      GradientStop {
        position: 1
        color: Qt.rgba(root.borderColor2.r, root.borderColor2.g,
                       root.borderColor2.b, root.borderAlpha)
      }
    }
  }

  Rectangle {
    id: inner
    x: root.leftWidth
    y: root.topWidth
    width: Math.max(0, parent.width - root.leftWidth - root.rightWidth)
    height: Math.max(0, parent.height - root.topWidth - root.bottomWidth)
    radius: Math.max(0, root.cornerRadius - Math.max(root.topWidth, root.rightWidth,
                                                     root.bottomWidth, root.leftWidth))
    color: root.backgroundColor
    clip: true

    Item {
      id: content
      anchors.fill: parent
    }
  }
}
