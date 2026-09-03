import QtQuick

// Bar item: music glyph, a small equaliser that animates only while playing,
// and the current track title.
//
// The title is elided to `maxWidth`, which Bar.qml derives from the space left
// between the workspaces on the left and the status/clock group on the right, so
// a long title can never collide with either. The widget is centred, so it grows
// and shrinks symmetrically about the middle of the bar.
Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  required property string screenName

  // Hard ceiling on the whole widget, including glyph and bars.
  property int maxWidth: root.s(220)

  readonly property bool playing: MediaState.isPlaying
  readonly property bool hasTrack: MediaState.hasTrack

  // Width the title may use, once the glyph, bars and spacing are accounted for.
  // Derives from maxWidth only, so it cannot form a binding loop with the Row's
  // implicit width.
  readonly property int titleSpace: Math.max(0,
      root.maxWidth - glyph.width - bars.width
      - content.spacing * 2 - root.s(12))

  implicitWidth: Math.min(root.maxWidth, content.implicitWidth + root.s(8))
  implicitHeight: root.s(20)
  clip: true

  Row {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: root.s(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.s(5)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: MediaState.glyphMusic
      font.family: Theme.glyphFamily
      font.pixelSize: root.s(14)
      color: root.playing ? Theme.text : Theme.textMuted
    }

    // Four bars at staggered durations. When not playing the animations stop
    // and every bar rests at its flat minimum. While playing with a live
    // cava feed, heights track the real spectrum (CavaState.levels);
    // otherwise they fall back to this animation.
    Row {
      id: bars
      anchors.verticalCenter: parent.verticalCenter
      height: root.s(14)
      spacing: root.s(2)

      Repeater {
        model: [520, 380, 460, 300]

        Rectangle {
          required property int modelData
          required property int index
          width: root.s(2)
          // 3 + level * 10 keeps the existing 3..13 geometry, with cava
          // levels (0..1) driving the height in place of the animation.
          height: root.spectrumActive ? root.s(3 + CavaState.levels[index] * 10) : root.s(3)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          color: root.playing ? Theme.accent : Theme.textMuted

          // Cava data only wins while audio is actually playing; otherwise
          // (paused, cava missing) the staggered animation below runs.
          readonly property bool spectrumActive:
              root.playing && CavaState.available

          SequentialAnimation on height {
            running: root.playing && !spectrumActive
            loops: Animation.Infinite
            // Staggered start so the bars do not move in lockstep.
            PauseAnimation { duration: index * 90 }
            NumberAnimation {
              to: root.s(13)
              duration: modelData
              easing.type: Easing.InOutSine
            }
            NumberAnimation {
              to: root.s(3)
              duration: modelData
              easing.type: Easing.InOutSine
            }
          }

          // No imperative reset: when playing goes false the height binding
          // above evaluates to the flat minimum, and the stopped animation
          // returns control of the property to the binding. An assignment
          // here (the old pattern) would permanently break the binding.
        }
      }
    }

    Text {
      id: title
      anchors.verticalCenter: parent.verticalCenter
      // Dropped entirely rather than elided down to a bare ellipsis when the
      // bar is too cramped to show anything useful (narrow monitor at a large
      // text scale). The glyph and bars still convey playback state.
      visible: root.hasTrack && root.titleSpace >= root.s(44)
      text: MediaState.trackTitle
      font.pixelSize: root.s(12)
      color: root.playing ? Theme.text : Theme.textMuted
      elide: Text.ElideRight
      // Measured via TextMetrics rather than this Text's own implicitWidth:
      // with elide enabled, reading implicitWidth from the width binding forms
      // a binding loop.
      // +2 because setting the width to exactly the measured natural width
      // makes Qt elide on sub-pixel rounding.
      width: visible ? Math.min(Math.ceil(titleMetrics.width) + 2, root.titleSpace) : 0
    }

    TextMetrics {
      id: titleMetrics
      font: title.font
      text: MediaState.trackTitle
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: MediaState.togglePanel(root.screenName)
  }

  MediaPanel {
    anchorItem: root
    ownerScreen: root.screenName
  }
}
