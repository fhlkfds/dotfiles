import QtQuick

// One item in the cover-flow carousel: the selected card in the centre, or a
// narrow skewed slice to one side.
//
// The depth illusion is built from width difference + overlap + perspective
// skew + dimming + z-order. No shaders, no 3D scene graph, no extra QML module.
//
// Structure, outermost first:
//
//   Item (this)          <- positioned by the carousel, warped by Matrix4x4
//     Item (clipper)     <- axis-aligned clip, so Qt can use a scissor clip
//       ThemePreview     <- design-size mockup, squeezed by Scale
//     dim / border / active dot
//
// The warp lives on the outer item so it carries the border and dim with it; the
// clip lives one level in so clipping stays axis-aligned and cheap.
Item {
  id: slice

  required property var entry
  // 0 for the selected card, negative to the left of centre, positive to the right.
  required property int relIndex
  property bool isActive: false
  property bool loadImage: true

  readonly property bool isSelected: slice.relIndex === 0
  readonly property bool leansRight: slice.relIndex > 0

  // Scaled design values, handed down by the carousel.
  property real skew: 0
  property real borderWidth: 1
  property real dimOpacity: 0
  property color borderColor: "transparent"
  property color dimColor: "black"
  property real cornerRadius: 6

  signal activated()

  // Nearer slices paint over farther ones, and the selected card over all of
  // them. A pure function of distance, so z never churns while navigating.
  z: slice.isSelected ? 1000 : -Math.abs(slice.relIndex)

  // ── perspective ────────────────────────────────────────────────────────────
  // A shear would give a parallelogram; the shape wanted here is a trapezoid, so
  // this needs a genuine perspective divide. Setting the fourth matrix row makes
  // w vary with x, and Qt Quick divides by w -- converging the horizontal edges.
  //
  // Composed as T(0,+H/2) . P(p) . T(0,-H/2) so the foreshortened outer edge
  // stays vertically centred (both corners pull in by `skew`). A bare P(p) would
  // anchor the shrink at the top instead.
  //
  //   k = (H - 2*skew)/H     how tall the outer edge ends up, as a fraction
  //   p = (1/k - 1)/W        so that w(W) = 1/k
  //
  // Verified against the corner mapping: inner edge keeps full height, outer
  // edge measures H - 2*skew, both mirrored correctly across the centre.
  readonly property real perspK:
    slice.height > 0 ? (slice.height - 2 * slice.skew) / slice.height : 1
  readonly property real perspP:
    (slice.width > 0 && slice.perspK > 0) ? (1 / slice.perspK - 1) / slice.width : 0

  transform: Matrix4x4 {
    matrix: {
      if (slice.isSelected || slice.perspP === 0)
        return Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
      const p = slice.perspP
      const w = slice.width
      const h = slice.height
      if (slice.leansRight) {
        // Inner edge on the left (x = 0), so the right edge foreshortens.
        return Qt.matrix4x4(1, 0, 0, 0,
                            h * p / 2, 1, 0, 0,
                            0, 0, 1, 0,
                            p, 0, 0, 1)
      }
      // Inner edge on the right (x = W), so the left edge foreshortens. Derived
      // by mirroring x about W and collapsing, rather than nesting a flip.
      return Qt.matrix4x4(1 - p * w, 0, 0, p * w * w,
                          -h * p / 2, 1, 0, h * p * w / 2,
                          0, 0, 1, 0,
                          -p, 0, 0, p * w + 1)
    }
  }

  // ── content ────────────────────────────────────────────────────────────────

  Item {
    id: clipper
    anchors.fill: parent
    clip: true

    ThemePreview {
      id: preview
      entry: slice.entry
      selected: slice.isSelected
      isActive: slice.isActive
      loadImage: slice.loadImage

      // The preview always lays out at design size; squeezing it into this
      // slot is what makes a slice look like a rotated card, and animating the
      // slot size is the collapse/expand transition.
      transform: Scale {
        xScale: preview.designW > 0 ? slice.width / preview.designW : 1
        yScale: preview.designH > 0 ? slice.height / preview.designH : 1
      }
    }
  }

  // Dim: the current theme's background over everything unselected, so sides
  // stay recognisable but clearly subordinate.
  Rectangle {
    anchors.fill: parent
    color: slice.dimColor
    opacity: slice.dimOpacity
    radius: slice.cornerRadius
    Behavior on opacity {
      NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: slice.cornerRadius
    border.width: slice.borderWidth
    border.color: slice.borderColor
    Behavior on border.width {
      NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
  }

  // Marks the theme that is actually applied, wherever it sits in the carousel.
  // Deliberately outside the squeezed content so it stays a dot rather than a
  // smear on a narrow slice.
  Rectangle {
    visible: slice.isActive
    width: Math.max(6, Math.round(slice.height * 0.022))
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Math.max(4, Math.round(slice.height * 0.018))
    color: slice.borderColor
    border.width: 1
    border.color: slice.dimColor
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    // Selecting and applying are different gestures: a side slice only moves
    // the selection, and only the centre card applies.
    onClicked: slice.activated()
  }
}
