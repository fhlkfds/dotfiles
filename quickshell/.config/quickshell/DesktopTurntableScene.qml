import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// The Turntable seen from above: a record whose label is the cover art, on a
// plinth with a tonearm, the sleeve tucked under its left edge, and the title
// and artist beneath the sleeve. The tonearm swings onto the record and the
// platter spins up while playing; both settle back when paused. A new cover
// fades in over the old one once it has loaded.
//
// Every length is a fraction of `unit`, the plinth's height, so one number
// scales the whole scene. Reads everything through `media` so the smoke
// harness can hand it a stand-in with the same shape as TurntableState.
Item {
  id: root

  property var media: TurntableState
  property real unit: Theme.fs(400)
  // The window turns this off while the workspace has windows over the scene,
  // so a hidden record does not keep the compositor drawing frames.
  property bool spinAllowed: true

  // MultiEffect draws nothing on Qt Quick's software backend (no GPU, broken
  // GL, QT_QUICK_BACKEND=software), which would blank the masked label and the
  // whole shadowed scene. There it goes without mask, shadow and sheen.
  readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software
  readonly property bool playing: media.hasTrack && media.isPlaying
  readonly property bool spinning: playing && spinAllowed && visible
  readonly property real shadowPad: unit * 0.08

  // DesktopClock fills the bottom-right corner, fs(56) from the edges and about
  // fs(112) tall. The scene is centred, so keeping it shorter than the screen
  // minus that band twice over keeps it clear of the clock on any output.
  readonly property int clockBand: Theme.fs(56 + 112 + 24)

  function unitFor(screenWidth, screenHeight) {
    const share = ({ wide: 0.45, mid: 0.6, close: 0.75 })[TurntableState.framing] || 0.6
    return Math.max(Theme.fs(160), Math.min(
      screenHeight * share,
      screenWidth * 0.9 / 1.65,
      screenHeight - clockBand * 2))
  }

  width: unit * 1.65
  height: unit

  opacity: media.hasTrack ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

  // 33 1/3 rpm, in degrees a second. Eased so the platter spins up and down.
  property real speed: spinning ? 200 : 0
  Behavior on speed { NumberAnimation { duration: 1600; easing.type: Easing.InOutQuad } }

  property real armAngle: playing ? 25 : 0
  Behavior on armAngle { NumberAnimation { duration: 1100; easing.type: Easing.InOutCubic } }

  FrameAnimation {
    running: root.speed > 0
    onTriggered: record.rotation = (record.rotation + root.speed * frameTime) % 360
  }

  readonly property color plinthColor: Theme.surface
  readonly property color metal: Qt.rgba(0.80, 0.80, 0.82, 1)
  readonly property color metalDark: Qt.rgba(0.36, 0.36, 0.38, 1)

  // Everything lives in one item so a single shadow falls under the plinth,
  // the sleeve and the caption alike.
  Item {
    id: scene
    anchors.fill: parent

    layer.enabled: root.effects
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: Theme.shadowColor
      shadowBlur: 1.0
      blurMax: 48
      shadowOpacity: 0.85
      shadowVerticalOffset: root.unit * 0.02
    }

    // --- sleeve and caption --------------------------------------------------

    Item {
      id: sleeve
      x: 0
      y: root.unit * 0.1
      width: root.unit * 0.66
      height: width
      rotation: -4

      Placeholder { anchors.fill: parent; radius: root.unit * 0.006 }
      Cover { id: sleeveArt; anchors.fill: parent; source: root.media.trackArtUrl }

      // Cardboard edge.
      Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
      }
    }

    Column {
      id: caption
      x: root.unit * 0.02
      y: root.unit * 0.81
      width: root.unit * 0.5
      spacing: root.unit * 0.008

      Text {
        width: parent.width
        text: root.media.trackTitle.toUpperCase()
        color: Theme.text
        font.family: Theme.uiFamily
        font.pixelSize: root.unit * 0.045
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: root.media.trackArtist
        color: Theme.textDim
        font.family: Theme.uiFamily
        font.pixelSize: root.unit * 0.032
        font.italic: true
        elide: Text.ElideRight
      }
    }

    // --- turntable -----------------------------------------------------------

    Rectangle {
      id: plinth
      x: root.unit * 0.55
      width: root.unit * 1.1
      height: root.unit
      radius: root.unit * 0.035
      border.width: 1
      border.color: Theme.hairline
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.lighter(root.plinthColor, 1.15) }
        GradientStop { position: 1; color: root.plinthColor }
      }

      // Platter rim, a little wider than the record.
      Rectangle {
        id: platter
        x: root.unit * 0.47 - width / 2
        y: root.unit * 0.5 - height / 2
        width: root.unit * 0.9
        height: width
        radius: width / 2
        color: Qt.darker(root.plinthColor, 1.6)
        border.width: Math.max(1, root.unit * 0.004)
        border.color: Qt.rgba(1, 1, 1, 0.18)
      }

      Item {
        id: record
        anchors.centerIn: platter
        width: root.unit * 0.86
        height: width

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(0.05, 0.05, 0.06, 1)
        }

        // Grooves: faint concentric rings between the label and the lead-in.
        Repeater {
          model: 16
          Rectangle {
            required property int index
            anchors.centerIn: parent
            width: record.width * (0.95 - index * 0.036)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, index % 3 === 0 ? 0.07 : 0.035)
          }
        }

        Item {
          id: label
          anchors.centerIn: parent
          width: record.width * 0.36
          height: width

          layer.enabled: root.effects
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: labelMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }

          Placeholder { anchors.fill: parent }
          Cover { anchors.fill: parent; source: root.media.trackArtUrl }
        }

        Rectangle {
          id: labelMask
          anchors.fill: label
          radius: width / 2
          visible: false
          layer.enabled: true
        }

        // Spindle.
        Rectangle {
          anchors.centerIn: parent
          width: root.unit * 0.022
          height: width
          radius: width / 2
          color: root.metal
          border.width: 1
          border.color: root.metalDark
        }
      }

      // Light catching the grooves: two opposed wedges that stay put while the
      // record turns under them.
      Shape {
        anchors.fill: record
        visible: root.effects
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: -1
          fillGradient: ConicalGradient {
            centerX: record.width / 2
            centerY: record.height / 2
            angle: 35
            GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.10; color: Qt.rgba(1, 1, 1, 0.09) }
            GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.60; color: Qt.rgba(1, 1, 1, 0.09) }
            GradientStop { position: 0.72; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0) }
          }
          PathAngleArc {
            centerX: record.width / 2
            centerY: record.height / 2
            radiusX: record.width / 2
            radiusY: record.height / 2
            startAngle: 0
            sweepAngle: 360
          }
        }
      }

      // Speed knob.
      Rectangle {
        x: root.unit * 0.98 - width / 2
        y: root.unit * 0.86 - height / 2
        width: root.unit * 0.08
        height: width
        radius: width / 2
        color: Qt.darker(root.plinthColor, 1.35)
        border.width: Math.max(1, root.unit * 0.004)
        border.color: Qt.rgba(1, 1, 1, 0.2)
      }

      // --- tonearm -----------------------------------------------------------

      Rectangle {
        id: pivot
        x: root.unit * 0.93 - width / 2
        y: root.unit * 0.17 - height / 2
        width: root.unit * 0.13
        height: width
        radius: width / 2
        color: root.metalDark
        border.width: Math.max(1, root.unit * 0.006)
        border.color: root.metal
      }

      // Pivots on the base; at rest it hangs straight down, clear of the record.
      Item {
        id: arm
        readonly property real back: root.unit * 0.1
        x: pivot.x + pivot.width / 2 - width / 2
        y: pivot.y + pivot.height / 2 - back
        width: root.unit * 0.07
        height: back + root.unit * 0.62
        transform: Rotation {
          origin.x: arm.width / 2
          origin.y: arm.back
          angle: root.armAngle
        }

        // Counterweight.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.unit * 0.055
          height: root.unit * 0.07
          radius: root.unit * 0.008
          color: root.metalDark
          border.width: 1
          border.color: root.metal
        }

        // Tube.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: arm.back * 0.5
          width: root.unit * 0.016
          height: parent.height - y - root.unit * 0.05
          radius: width / 2
          color: root.metal
        }

        // Headshell and cartridge.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          width: root.unit * 0.045
          height: root.unit * 0.075
          radius: root.unit * 0.006
          rotation: 18
          color: root.metal
          border.width: 1
          border.color: root.metalDark

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.12
            width: parent.width * 0.6
            height: parent.height * 0.35
            radius: root.unit * 0.003
            color: Theme.accent
          }
        }
      }

      // Cap over the pivot, drawn above the arm.
      Rectangle {
        anchors.centerIn: pivot
        width: pivot.width * 0.42
        height: width
        radius: width / 2
        color: root.metal
        border.width: 1
        border.color: root.metalDark
      }
    }
  }

  // Shown where there is no cover yet, or the player gives none.
  component Placeholder: Rectangle {
    color: Theme.bgDeep

    Text {
      anchors.centerIn: parent
      text: MediaState.glyphMusic
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Math.max(1, parent.width * 0.3)
    }
  }

  // Two images taking turns: the next cover loads into the hidden one, which
  // only fades in once it is ready, so the old cover stays up meanwhile.
  component Cover: Item {
    id: cover
    property string source: ""
    property Image front: null
    property Image back: one

    onSourceChanged: back.source = source
    Component.onCompleted: back.source = source

    function settle(img) {
      if (img !== back || img.status === Image.Loading)
        return
      back = front === null ? (img === one ? two : one) : front
      front = img
    }

    Image {
      id: one
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      sourceSize { width: 800; height: 800 }
      asynchronous: true
      smooth: true
      opacity: cover.front === one && status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 700 } }
      onStatusChanged: cover.settle(one)
    }

    Image {
      id: two
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      sourceSize { width: 800; height: 800 }
      asynchronous: true
      smooth: true
      opacity: cover.front === two && status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 700 } }
      onStatusChanged: cover.settle(two)
    }
  }
}
