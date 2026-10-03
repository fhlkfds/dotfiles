import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// The Turntable: a desk against a wall at night, modelled on Vinyl for Mac's
// "After Hours" scene. The sleeve of the playing album stands on the left, the
// record turns in the middle with the cover as its label, recently played
// covers lie in a pile on the right under a glass lamp, and the current
// wallpaper hangs in a backlit frame above.
//
// The tonearm swings onto the record and the platter spins up while playing;
// both settle back when paused. A new cover fades in over the old one once it
// has loaded. The whole scene fades out when the player goes idle.
//
// Layout is in the pixels of a 1300x724 reference frame, scaled by `k` to fit
// the screen; the wall and desk run on past it to the screen edges. Things
// lying on the desk are drawn flat and squashed by `tilt` for the camera angle.
// Reads everything through `media` so the smoke harness can hand it a stand-in
// with the same shape as TurntableState.
Item {
  id: root

  property var media: TurntableState
  // The window turns this off while the workspace has windows over the scene,
  // so a hidden record does not keep the compositor drawing frames.
  property bool spinAllowed: true

  // MultiEffect and Shape draw nothing on Qt Quick's software backend (no GPU,
  // broken GL, QT_QUICK_BACKEND=software). There the scene goes without
  // shadows, glows and the round label mask rather than going blank.
  readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software
  readonly property bool playing: media.hasTrack && media.isPlaying
  readonly property bool spinning: playing && spinAllowed && visible

  readonly property real k: Math.min(width / 1300, height / 724)
  function r(n) { return n * k }
  readonly property real tilt: 0.41

  clip: true
  opacity: media.hasTrack ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

  // 33 1/3 rpm, in degrees a second. Eased so the platter spins up and down.
  property real speed: spinning ? 200 : 0
  Behavior on speed { NumberAnimation { duration: 1600; easing.type: Easing.InOutQuad } }

  // 0 is the tonearm at rest, 1 is the stylus in the groove.
  property real armDown: playing ? 1 : 0
  Behavior on armDown { NumberAnimation { duration: 1100; easing.type: Easing.InOutCubic } }

  FrameAnimation {
    running: root.speed > 0
    onTriggered: record.rotation = (record.rotation + root.speed * frameTime) % 360
  }

  // --- palette: lamplight, not theme roles; the scene is a photograph --------

  readonly property color wallColor: Qt.rgba(0.40, 0.23, 0.16, 1)
  readonly property color lampLight: Qt.rgba(1.00, 0.82, 0.66, 1)
  readonly property color ledLight: Qt.rgba(1.00, 0.52, 0.22, 1)
  readonly property color cream: Qt.rgba(0.86, 0.82, 0.75, 1)
  readonly property color brass: Qt.rgba(0.72, 0.56, 0.34, 1)
  readonly property color brassDark: Qt.rgba(0.36, 0.25, 0.13, 1)
  readonly property color metal: Qt.rgba(0.78, 0.76, 0.73, 1)
  readonly property color metalDark: Qt.rgba(0.30, 0.29, 0.28, 1)
  readonly property color paper: Qt.rgba(0.86, 0.83, 0.78, 1)
  readonly property url wood: Qt.resolvedUrl("turntable/wood.jpg")

  // --- the room: wall and desk run to the screen edges ----------------------

  readonly property real deskY: stage.y + r(395)

  Rectangle {
    width: root.width
    height: root.deskY
    color: root.wallColor
  }

  Item {
    id: desk
    y: root.deskY
    width: root.width
    height: root.height - root.deskY
    clip: true

    // Grain runs along the desk and closes up with distance.
    Image {
      width: parent.width
      height: parent.height / root.tilt
      source: root.wood
      fillMode: Image.Tile
      sourceSize { width: root.r(760); height: root.r(760) }
      transform: Scale { yScale: root.tilt }
    }

    // Catches the lamplight at the back, falls into shadow at the front.
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 0.62, 0.38, 0.22) }
        GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0) }
        GradientStop { position: 1; color: Qt.rgba(0.04, 0.01, 0, 0.55) }
      }
    }
  }

  // Where the desk meets the wall.
  Rectangle {
    y: root.deskY - height
    width: root.width
    height: root.r(3)
    color: Qt.rgba(0.05, 0.02, 0.01, 0.45)
  }
  Rectangle {
    y: root.deskY
    width: root.width
    height: root.r(2)
    color: Qt.rgba(1, 0.75, 0.55, 0.25)
  }

  Item {
    id: stage
    width: root.r(1300)
    height: root.r(724)
    x: (root.width - width) / 2
    y: (root.height - height) / 2

    // --- light --------------------------------------------------------------

    Glow { cx: root.r(1185); cy: root.r(280); radius: root.r(820); tint: root.lampLight }
    Glow { cx: root.r(1185); cy: root.r(280); radius: root.r(320); tint: Qt.rgba(1, 0.88, 0.74, 0.7) }
    Glow { cx: root.r(-40); cy: root.r(400); radius: root.r(620); tint: Qt.rgba(1, 0.72, 0.50, 0.9) }
    Glow { cx: root.r(1160); cy: root.r(470); radius: root.r(480); squash: 0.3; tint: Qt.rgba(1, 0.66, 0.36, 0.6) }
    Glow { cx: root.r(20); cy: root.r(470); radius: root.r(420); squash: 0.35; tint: Qt.rgba(1, 0.58, 0.30, 0.45) }

    // --- picture frame, lit from behind ---------------------------------------

    Rectangle {
      id: frame
      x: root.r(634)
      y: root.r(-24)
      width: root.r(354)
      height: root.r(172)
      color: Qt.rgba(0.20, 0.13, 0.09, 1)

      layer.enabled: root.effects
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.ledLight
        shadowBlur: 1.0
        blurMax: 64
        shadowOpacity: 1
        shadowScale: 1.04
      }

      Rectangle {
        id: mat
        anchors.fill: parent
        anchors.margins: root.r(14)
        color: root.paper

        Rectangle {
          x: root.r(32)
          width: parent.width - root.r(64)
          height: parent.height - root.r(30)
          color: Qt.rgba(0.08, 0.07, 0.06, 1)
          clip: true

          Image {
            anchors.fill: parent
            source: root.media.wallpaper ? "file://" + root.media.wallpaper : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize { width: 640; height: 640 }
            asynchronous: true
          }

          // Night: the picture is only lit from behind the frame.
          Rectangle { anchors.fill: parent; color: Qt.rgba(0.05, 0.02, 0, 0.45) }
        }

        // Lamplight across the glass.
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0.1, 0.04, 0, 0.25) }
            GradientStop { position: 1; color: Qt.rgba(1, 0.8, 0.6, 0.12) }
          }
        }
      }
    }

    // --- sleeve on its stand --------------------------------------------------

    Item {
      id: sleeveStand
      x: root.r(100)
      y: root.r(246)
      width: root.r(338)
      height: root.r(342)

      layer.enabled: root.effects
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0.05, 0.01, 0, 1)
        shadowBlur: 0.9
        blurMax: 40
        shadowOpacity: 0.75
        shadowHorizontalOffset: root.r(10)
        shadowVerticalOffset: root.r(6)
      }

      Item {
        id: sleeve
        x: root.r(8)
        width: root.r(310)
        height: root.r(310)

        Placeholder { anchors.fill: parent }
        Cover { anchors.fill: parent; source: root.media.trackArtUrl }

        // Lamplight from the right, falling off to the left.
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0.08, 0.03, 0, 0.35) }
            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1; color: Qt.rgba(1, 0.75, 0.5, 0.08) }
          }
        }
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.width: Math.max(1, root.r(1.5))
          border.color: Qt.rgba(1, 0.9, 0.8, 0.18)
        }
      }

      // The stand: a lip behind the sleeve, the plank's top and its front.
      Rectangle {
        x: root.r(12)
        y: root.r(300)
        width: root.r(322)
        height: root.r(10)
        color: Qt.rgba(0.20, 0.12, 0.07, 1)
      }
      Rectangle {
        x: root.r(12)
        y: root.r(306)
        width: root.r(322)
        height: root.r(10)
        color: Qt.rgba(0.62, 0.43, 0.26, 1)
      }
      WoodFace {
        x: root.r(12)
        y: root.r(316)
        width: root.r(322)
        height: root.r(24)
        shade: 0.35
      }
    }

    // --- turntable ------------------------------------------------------------

    Item {
      id: body
      x: root.r(480)
      y: root.r(400)
      width: root.r(405)
      height: root.r(182)

      layer.enabled: root.effects
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0.05, 0.01, 0, 1)
        shadowBlur: 1.0
        blurMax: 48
        shadowOpacity: 0.8
        shadowVerticalOffset: root.r(8)
      }

      // Top deck, brighter on the lamp's side.
      Rectangle {
        width: parent.width
        height: root.r(136)
        radius: root.r(4)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: Qt.darker(root.cream, 1.35) }
          GradientStop { position: 1; color: root.cream }
        }
      }
      Rectangle {
        y: root.r(134)
        width: parent.width
        height: root.r(3)
        color: Qt.rgba(1, 0.95, 0.88, 0.55)
      }
      WoodFace {
        y: root.r(137)
        width: parent.width
        height: root.r(45)
        shade: 0.25
      }

      // Speed knob and power light, left of where the tonearm rests.
      Rectangle {
        x: root.r(292)
        y: root.r(104)
        width: root.r(19)
        height: root.r(13)
        radius: height / 2
        gradient: Gradient {
          GradientStop { position: 0; color: root.brass }
          GradientStop { position: 1; color: root.brassDark }
        }
      }
      Rectangle {
        x: root.r(270)
        y: root.r(115)
        width: root.r(6)
        height: root.r(5)
        radius: height / 2
        color: Qt.rgba(0.08, 0.07, 0.06, 1)
      }
    }

    // The deck seen flat from above, squashed for the camera. Lengths inside
    // are on the deck itself; `d(n)` lifts a screen-space depth onto it.
    Item {
      id: deck
      x: root.r(480)
      y: root.r(400)
      width: root.r(405)
      height: root.r(136) / root.tilt
      transform: Scale { yScale: root.tilt }

      function d(n) { return root.r(n) / root.tilt }
      readonly property real cx: root.r(140)
      readonly property real cy: d(46)

      // Platter rim: stacked rings read as the ribbed edge below the record.
      Repeater {
        model: 5
        Rectangle {
          required property int index
          x: deck.cx - width / 2
          y: deck.cy - height / 2 + deck.d(16 - index * 3)
          width: root.r(288)
          height: width
          radius: width / 2
          color: index % 2 === 0 ? Qt.darker(root.metal, 1.5) : root.metal
        }
      }

      // The record's own edge, then the record.
      Rectangle {
        x: deck.cx - width / 2
        y: deck.cy - height / 2 + deck.d(3)
        width: root.r(280)
        height: width
        radius: width / 2
        color: Qt.rgba(0.02, 0.02, 0.02, 1)
      }

      Item {
        id: record
        x: deck.cx - width / 2
        y: deck.cy - height / 2
        width: root.r(280)
        height: width

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(0.06, 0.055, 0.055, 1)
        }

        // Grooves: faint concentric rings between the label and the lead-in.
        Repeater {
          model: 14
          Rectangle {
            required property int index
            anchors.centerIn: parent
            width: record.width * (0.94 - index * 0.041)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 0.9, 0.8, index % 3 === 0 ? 0.08 : 0.04)
          }
        }

        Item {
          id: label
          anchors.centerIn: parent
          width: record.width * 0.34
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
          width: root.r(7)
          height: width
          radius: width / 2
          color: root.metal
        }
      }

      // Lamplight catching the grooves: two opposed wedges that stay put while
      // the record turns under them.
      Shape {
        anchors.fill: record
        visible: root.effects
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: -1
          fillGradient: ConicalGradient {
            centerX: record.width / 2
            centerY: record.height / 2
            angle: 20
            GradientStop { position: 0.00; color: Qt.rgba(1, 0.85, 0.7, 0) }
            GradientStop { position: 0.08; color: Qt.rgba(1, 0.85, 0.7, 0.16) }
            GradientStop { position: 0.18; color: Qt.rgba(1, 0.85, 0.7, 0) }
            GradientStop { position: 0.50; color: Qt.rgba(1, 0.85, 0.7, 0) }
            GradientStop { position: 0.58; color: Qt.rgba(1, 0.85, 0.7, 0.10) }
            GradientStop { position: 0.68; color: Qt.rgba(1, 0.85, 0.7, 0) }
            GradientStop { position: 1.00; color: Qt.rgba(1, 0.85, 0.7, 0) }
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

      // Tonearm base.
      Rectangle {
        x: root.r(345) - width / 2
        y: deck.d(18) - height / 2
        width: root.r(46)
        height: width
        radius: width / 2
        color: root.metalDark
      }
    }

    // --- tonearm --------------------------------------------------------------
    //
    // It swings on the deck about the pivot, between resting beside the record
    // and the stylus in the groove; the arm itself is raised above the deck, so
    // each end is projected onto the deck and lifted by its height.

    Item {
      id: tonearm
      readonly property real px: 345
      readonly property real py: 44      // on the deck, before the squash
      readonly property real reach: 262
      readonly property real angle: (88 + root.armDown * 50) * Math.PI / 180
      readonly property real lift: 38
      readonly property real tipLift: 26 - root.armDown * 18

      // Screen positions, in reference pixels.
      readonly property real baseX: 480 + px
      readonly property real baseY: 400 + py * root.tilt
      readonly property real topY: baseY - lift
      readonly property real tipX: baseX + reach * Math.cos(angle)
      readonly property real tipY: 400 + (py + reach * Math.sin(angle)) * root.tilt - tipLift
      readonly property real armLength: Math.hypot(tipX - baseX, tipY - topY)
      readonly property real armAngle: Math.atan2(tipY - topY, tipX - baseX) * 180 / Math.PI

      // Post.
      Rectangle {
        x: root.r(tonearm.baseX - 7)
        y: root.r(tonearm.topY)
        width: root.r(14)
        height: root.r(tonearm.lift)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: root.metalDark }
          GradientStop { position: 0.6; color: root.metal }
          GradientStop { position: 1; color: root.metalDark }
        }
      }

      // Counterweight, behind the pivot.
      Rectangle {
        x: root.r(tonearm.baseX)
        y: root.r(tonearm.topY) - height / 2
        width: root.r(42)
        height: root.r(17)
        radius: root.r(4)
        transformOrigin: Item.Left
        rotation: tonearm.armAngle + 180
        gradient: Gradient {
          GradientStop { position: 0; color: root.metal }
          GradientStop { position: 1; color: root.metalDark }
        }
      }

      // Arm.
      Rectangle {
        x: root.r(tonearm.baseX)
        y: root.r(tonearm.topY) - height / 2
        width: root.r(tonearm.armLength)
        height: root.r(5)
        radius: height / 2
        transformOrigin: Item.Left
        rotation: tonearm.armAngle
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.lighter(root.metal, 1.15) }
          GradientStop { position: 1; color: root.metalDark }
        }
      }

      // Headshell and cartridge.
      Rectangle {
        x: root.r(tonearm.tipX) - width / 2
        y: root.r(tonearm.tipY) - height / 2
        width: root.r(30)
        height: root.r(12)
        radius: root.r(2)
        rotation: tonearm.armAngle
        color: Qt.rgba(0.12, 0.11, 0.10, 1)
        border.width: 1
        border.color: root.metalDark
      }

      // Pivot cap.
      Rectangle {
        x: root.r(tonearm.baseX) - width / 2
        y: root.r(tonearm.topY) - height / 2
        width: root.r(24)
        height: root.r(11)
        radius: height / 2
        color: Qt.lighter(root.metal, 1.1)
      }
    }

    // --- pile of recent covers ------------------------------------------------

    Item {
      id: pile
      x: root.r(940)
      y: root.r(468)
      width: root.r(320)
      height: root.r(320)
      transform: Scale { yScale: root.tilt }

      layer.enabled: root.effects
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0.05, 0.01, 0, 1)
        shadowBlur: 0.8
        blurMax: 32
        shadowOpacity: 0.7
        shadowVerticalOffset: root.r(8)
      }

      // Oldest at the bottom; empty slots are plain sleeves.
      Repeater {
        model: 4
        Rectangle {
          required property int index
          readonly property int age: 3 - index
          readonly property string art: age < root.media.recentCovers.length
            ? root.media.recentCovers[age] : ""
          anchors.fill: parent
          anchors.topMargin: root.r(age * 6) / root.tilt
          anchors.bottomMargin: -anchors.topMargin
          rotation: [-3, 5, -7, 2][index]
          color: root.paper

          Rectangle {
            anchors.fill: parent
            anchors.margins: root.r(3)
            color: [Qt.rgba(0.30, 0.22, 0.18, 1), Qt.rgba(0.18, 0.16, 0.15, 1),
                    Qt.rgba(0.42, 0.30, 0.22, 1), Qt.rgba(0.24, 0.20, 0.18, 1)][index]
          }
          Image {
            anchors.fill: parent
            anchors.margins: root.r(3)
            source: parent.art
            fillMode: Image.PreserveAspectCrop
            sourceSize { width: 512; height: 512 }
            asynchronous: true
          }
          // Lower covers sit in the shade of the ones above.
          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.05, 0.02, 0, parent.age * 0.12)
          }
        }
      }
    }

    // --- lamp -----------------------------------------------------------------

    Item {
      id: lamp
      x: root.r(1100)
      y: root.r(176)
      width: root.r(170)
      height: root.r(285)

      // Cord, dropping off the back of the desk.
      Shape {
        anchors.fill: parent
        visible: root.effects
        ShapePath {
          strokeColor: Qt.rgba(0.06, 0.04, 0.03, 1)
          strokeWidth: root.r(3)
          fillColor: "transparent"
          startX: root.r(118); startY: root.r(268)
          PathCubic {
            x: root.r(250); y: root.r(219)
            control1X: root.r(170); control1Y: root.r(274)
            control2X: root.r(215); control2Y: root.r(222)
          }
        }
      }

      // Foot, stem and collar.
      Rectangle {
        x: root.r(28)
        y: root.r(244)
        width: root.r(104)
        height: root.r(36)
        radius: height / 2
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.lighter(root.brass, 1.2) }
          GradientStop { position: 1; color: root.brassDark }
        }
      }
      Rectangle {
        x: root.r(72)
        y: root.r(204)
        width: root.r(18)
        height: root.r(48)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: root.brassDark }
          GradientStop { position: 0.6; color: Qt.lighter(root.brass, 1.25) }
          GradientStop { position: 1; color: root.brassDark }
        }
      }
      Rectangle {
        x: root.r(56)
        y: root.r(200)
        width: root.r(50)
        height: root.r(12)
        radius: root.r(3)
        color: root.brass
      }

      // Ribbed glass dome, with the bulb shining through it.

      Rectangle {
        id: dome
        x: root.r(4)
        width: root.r(156)
        height: root.r(208)
        topLeftRadius: width / 2
        topRightRadius: width / 2
        bottomLeftRadius: root.r(6)
        bottomRightRadius: root.r(6)
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(1, 0.88, 0.74, 0.50) }
          GradientStop { position: 0.6; color: Qt.rgba(1, 0.80, 0.60, 0.55) }
          GradientStop { position: 1; color: Qt.rgba(0.96, 0.64, 0.40, 0.72) }
        }
        border.width: Math.max(1, root.r(1.5))
        border.color: Qt.rgba(1, 0.92, 0.8, 0.45)

        Repeater {
          model: 11
          Rectangle {
            required property int index
            readonly property real t: (index + 1) / 12
            // Ribs start lower towards the edges, following the dome's curve.
            readonly property real rise: dome.width / 2 * (1 - Math.sqrt(1 - Math.pow(2 * t - 1, 2)))
            x: dome.width * t - width / 2
            y: rise + root.r(6)
            width: Math.max(1, root.r(2))
            height: dome.height - y - root.r(4)
            color: index % 2 === 0 ? Qt.rgba(1, 0.97, 0.90, 0.35) : Qt.rgba(0.55, 0.30, 0.16, 0.18)
          }
        }
      }

      Glow { cx: root.r(82); cy: root.r(112); radius: root.r(150); squash: 1.2; tint: Qt.rgba(1, 0.90, 0.70, 1) }
      Rectangle {
        x: root.r(64)
        y: root.r(64)
        width: root.r(36)
        height: root.r(72)
        radius: width / 2
        color: Qt.rgba(1, 0.99, 0.94, 1)
        layer.enabled: root.effects
        layer.effect: MultiEffect { blurEnabled: true; blur: 0.7; blurMax: 32 }
      }
    }
  }

  // Corners fall away into the dark.
  Shape {
    anchors.fill: parent
    visible: root.effects
    ShapePath {
      strokeWidth: -1
      fillGradient: RadialGradient {
        centerX: root.width / 2
        centerY: root.height / 2
        centerRadius: Math.hypot(root.width, root.height) / 2
        focalX: centerX
        focalY: centerY
        GradientStop { position: 0.55; color: Qt.rgba(0.05, 0.02, 0.01, 0) }
        GradientStop { position: 1.0; color: Qt.rgba(0.05, 0.02, 0.01, 0.6) }
      }
      startX: 0; startY: 0
      PathLine { x: root.width; y: 0 }
      PathLine { x: root.width; y: root.height }
      PathLine { x: 0; y: root.height }
      PathLine { x: 0; y: 0 }
    }
  }

  // A soft round pool of light, centred on (cx, cy); `squash` flattens it
  // into an ellipse for light lying on the desk.
  component Glow: Shape {
    id: glow
    property real cx: 0
    property real cy: 0
    property real radius: 100
    property real squash: 1
    property color tint: "white"

    visible: root.effects
    x: cx - radius
    y: cy - radius
    width: radius * 2
    height: radius * 2
    transform: Scale { origin.y: glow.radius; yScale: glow.squash }

    ShapePath {
      strokeWidth: -1
      fillGradient: RadialGradient {
        centerX: glow.radius
        centerY: glow.radius
        centerRadius: glow.radius
        focalX: glow.radius
        focalY: glow.radius
        GradientStop { position: 0.0; color: glow.tint }
        GradientStop { position: 0.35; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, glow.tint.a * 0.45) }
        GradientStop { position: 1.0; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, 0) }
      }
      startX: 0; startY: 0
      PathLine { x: glow.width; y: 0 }
      PathLine { x: glow.width; y: glow.height }
      PathLine { x: 0; y: glow.height }
      PathLine { x: 0; y: 0 }
    }
  }

  // Wood seen edge-on: the desk texture, darkened by `shade`.
  component WoodFace: Item {
    property real shade: 0.3
    clip: true

    Image {
      anchors.fill: parent
      source: root.wood
      fillMode: Image.Tile
      sourceSize { width: root.r(500); height: root.r(500) }
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.05, 0.02, 0, parent.shade) }
  }

  // Shown where there is no cover yet, or the player gives none.
  component Placeholder: Rectangle {
    color: Qt.rgba(0.07, 0.06, 0.06, 1)

    Text {
      anchors.centerIn: parent
      text: MediaState.glyphMusic
      color: Qt.rgba(1, 0.9, 0.8, 0.35)
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
