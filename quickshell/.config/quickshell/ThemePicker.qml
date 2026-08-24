pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Fullscreen cover-flow theme carousel, bound to Super+Ctrl+Shift+Space.
//
// One dominant preview in the centre, narrow overlapping skewed slices running
// off both edges. Same layer-shell shape as the keybindings palette: an
// overlay-layer surface covering the screen, exclusive keyboard focus, no space
// reserved. One instance per monitor (see Bar.qml), but only the one whose
// ownerScreen matches ThemeState.panelScreen is visible, so a keybind opens
// exactly one overlay on the focused output.
//
// Nothing here applies a theme. Navigation only moves selectedIndex; the backend
// is reached solely through ThemeState.activate(), from Enter or a click on the
// centre card.
PanelWindow {
  id: panel

  required property string ownerScreen

  visible: ThemeState.panelVisible
        && ThemeState.panelScreen === panel.ownerScreen

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-theme-picker"

  // ── responsive scale ───────────────────────────────────────────────────────
  // Everything is authored in design space and multiplied by one factor, so the
  // aspect ratio can never drift. Driven by monitor geometry only, not by the
  // Text Size setting: a preview is a picture of a desktop, and scaling it with
  // the UI font would overflow a portrait monitor.
  //
  // requiredW leaves room for the centre plus roughly two slices a side, so the
  // thing still reads as a carousel rather than a lone card.
  readonly property real requiredW: Theme.coverSelectedW + 4 * Theme.coverItemStep
  readonly property real requiredH:
    Theme.coverTopMargin + Theme.coverSelectedH + Theme.coverLabelGap
    + Theme.coverLabelH + Theme.coverFilterH + Theme.coverTopMargin

  readonly property real s: Math.min(1.0,
    panel.width / panel.requiredW,
    panel.height / panel.requiredH)

  readonly property real selW: Theme.coverSelectedW * panel.s
  readonly property real selH: Theme.coverSelectedH * panel.s
  readonly property real sliceW: Theme.coverSliceW * panel.s
  readonly property real sliceH: Theme.coverSliceH * panel.s
  readonly property real step: Theme.coverItemStep * panel.s
  readonly property real skew: Theme.coverSkew * panel.s

  // Selected card is always centred; the carousel is laid out around it.
  readonly property real centreX: (panel.width - panel.selW) / 2
  readonly property real centreY:
    (panel.height - panel.selH - Theme.coverLabelGap * panel.s
     - Theme.coverLabelH * panel.s) / 2

  readonly property int count: ThemeState.filtered.length
  readonly property int current: ThemeState.selectedIndex

  function commit() {
    ThemeState.activate()
  }

  // Escape undoes the narrowing first, and only closes when there is nothing
  // left to undo.
  function dismiss() {
    if (ThemeState.query !== "") {
      ThemeState.clearQuery()
      return
    }
    ThemeState.close()
  }

  // ── scrim ──────────────────────────────────────────────────────────────────
  // The active theme's background, not the browsed one.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.coverScrimOpacity)
    opacity: panel.shown ? 1 : 0
    Behavior on opacity {
      NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: ThemeState.close()
    }
  }

  property bool shown: false

  // ── keyboard ───────────────────────────────────────────────────────────────
  // There is no search box. The overlay itself takes every key, which is what
  // lets Left/Right drive the carousel instead of a text caret, and lets typing
  // filter without anything to click first.
  FocusScope {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: event => {
      switch (event.key) {
      case Qt.Key_Escape:
        panel.dismiss(); event.accepted = true; return
      case Qt.Key_Return:
      case Qt.Key_Enter:
        panel.commit(); event.accepted = true; return
      case Qt.Key_Left:
      case Qt.Key_Backtab:
        ThemeState.moveSelection(-1); event.accepted = true; return
      case Qt.Key_Right:
        ThemeState.moveSelection(1); event.accepted = true; return
      case Qt.Key_Tab:
        // Shift+Tab arrives as Key_Tab with the modifier on some layouts and as
        // Key_Backtab on others, so both spellings are handled.
        ThemeState.moveSelection((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
        event.accepted = true; return
      case Qt.Key_Home:
        ThemeState.selectFirst(); event.accepted = true; return
      case Qt.Key_End:
        ThemeState.selectLast(); event.accepted = true; return
      case Qt.Key_Backspace:
        ThemeState.backspaceQuery(); event.accepted = true; return
      }

      // Anything that produced a printable character becomes filter input.
      // Guarding on the control modifier keeps chords out of the query.
      if (event.text.length > 0
          && event.text.charCodeAt(0) >= 0x20
          && !(event.modifiers & Qt.ControlModifier)
          && !(event.modifiers & Qt.AltModifier)) {
        ThemeState.appendToQuery(event.text)
        event.accepted = true
      }
    }

    // ── carousel ─────────────────────────────────────────────────────────────

    Item {
      id: carousel
      anchors.fill: parent
      opacity: panel.shown ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
      }

      // Only the neighbourhood is built. Everything past the radius is neither
      // instantiated nor allowed to fetch a wallpaper.
      // How many slices exist at once, and where the centre sits among them.
      // Deriving `half` from the actual built count (rather than assuming the
      // full 2*radius+1) is what keeps the selected item in the middle when a
      // filter has narrowed the set to fewer items than the radius.
      readonly property int built:
        Math.min(panel.count, 2 * Theme.coverVisibleRadius + 1)
      readonly property int half: Math.floor(carousel.built / 2)

      Repeater {
        id: rep
        model: carousel.built

        delegate: ThemeSlice {
          id: sliceItem
          required property int index

          // Offset from the selected item. The window of built slices follows
          // the selection rather than the start of the model, and wraps the same
          // way navigation does -- so there is always something either side.
          readonly property int offset: sliceItem.index - carousel.half
          readonly property int modelIndex:
            panel.count > 0
              ? ((panel.current + sliceItem.offset) % panel.count + panel.count) % panel.count
              : 0

          entry: panel.count > 0 ? ThemeState.filtered[sliceItem.modelIndex] : null
          relIndex: sliceItem.offset
          isActive: sliceItem.entry
                 && sliceItem.entry.slug === ThemeState.activeSlug
          // Since built <= count, no two slices share a modelIndex, so there is
          // nothing to hide.
          loadImage: Math.abs(sliceItem.offset) <= Theme.coverLoadRadius
          visible: panel.count > 0

          // Geometry. Neighbours sit outside the centre block and advance by
          // `step`, so with sliceW 108 and step 78 adjacent slices overlap by
          // 30 and the nearest one's inner edge is flush with the centre card.
          width: sliceItem.relIndex === 0 ? panel.selW : panel.sliceW
          height: sliceItem.relIndex === 0 ? panel.selH : panel.sliceH
          x: {
            if (sliceItem.relIndex === 0)
              return panel.centreX
            if (sliceItem.relIndex > 0)
              return panel.centreX + panel.selW
                   + (sliceItem.relIndex - 1) * panel.step
            return panel.centreX - (-sliceItem.relIndex - 1) * panel.step
                 - panel.sliceW
          }
          // Slices are vertically centred against the selected card.
          y: panel.centreY + (panel.selH - height) / 2

          skew: sliceItem.relIndex === 0 ? 0 : panel.skew
          cornerRadius: Math.max(2, 8 * panel.s)
          borderWidth: (sliceItem.relIndex === 0
                        ? Theme.coverSelectedBorder
                        : Theme.coverSliceBorder) * panel.s
          borderColor: sliceItem.relIndex === 0
            ? Theme.borderActive1
            : Qt.rgba(Theme.borderActive1.r, Theme.borderActive1.g,
                      Theme.borderActive1.b, 0.35)
          dimColor: Theme.bg
          dimOpacity: sliceItem.relIndex === 0 ? 0 : Theme.coverSideDim

          // Collapse/expand: the centre grows out of a slice while the old
          // centre shrinks into one.
          Behavior on x {
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
          }
          Behavior on width {
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
          }
          Behavior on height {
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
          }
          Behavior on y {
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
          }

          onActivated: {
            if (sliceItem.relIndex === 0) {
              // Clicking the card already in the centre applies it.
              panel.commit()
            } else {
              // Clicking a side slice only brings it to the centre.
              ThemeState.moveSelection(sliceItem.relIndex)
            }
          }
        }
      }

      // ── label ──────────────────────────────────────────────────────────────
      // Only the focused theme's name. Never baked into the preview.
      Text {
        id: nameLabel
        width: panel.selW
        x: panel.centreX
        y: panel.centreY + panel.selH + Theme.coverLabelGap * panel.s
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight

        text: ThemeState.selected ? ThemeState.selected.name
                                  : ThemeState.statusText
        color: Theme.text
        font.family: Theme.uiFamily
        font.pixelSize: Math.round(Theme.coverLabelFont * panel.s)
        font.weight: Font.DemiBold

        // Keeps the name readable over a bright wallpaper edge without adding
        // a heavy effect.
        style: Text.Outline
        styleColor: Qt.rgba(Theme.bgDeep.r, Theme.bgDeep.g, Theme.bgDeep.b, 0.55)
      }

      // The filter echo appears only while filtering -- there is no permanent
      // search field.
      Text {
        id: filterLabel
        visible: ThemeState.query !== ""
        width: panel.selW
        x: panel.centreX
        y: nameLabel.y + nameLabel.height + Math.round(6 * panel.s)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight

        text: ThemeState.query
        color: Theme.textDim
        opacity: 0.85
        font.family: Theme.uiFamily
        font.pixelSize: Math.round(Theme.coverFilterFont * panel.s)
      }

      // Restrained error line. The overlay stays open when the backend fails, so
      // this is where the reason shows up.
      Text {
        visible: ThemeState.lastError !== ""
        width: panel.selW
        x: panel.centreX
        y: filterLabel.visible
           ? filterLabel.y + filterLabel.height + Math.round(6 * panel.s)
           : nameLabel.y + nameLabel.height + Math.round(6 * panel.s)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight

        text: ThemeState.lastError
        color: Theme.error
        font.family: Theme.uiFamily
        font.pixelSize: Math.round(Theme.coverFilterFont * panel.s)
      }

      // Wheel / touchpad: one theme per gesture. Raw deltas would fly through
      // the whole set, so they are accumulated to a threshold.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true

        property real accum: 0

        onWheel: wheel => {
          const d = (wheel.angleDelta.x !== 0)
            ? wheel.angleDelta.x : wheel.angleDelta.y
          accum += d
          while (Math.abs(accum) >= 120) {
            ThemeState.moveSelection(accum > 0 ? -1 : 1)
            accum += (accum > 0 ? -120 : 120)
          }
          wheel.accepted = true
        }
      }
    }
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  onVisibleChanged: {
    if (!visible) {
      panel.shown = false
      return
    }
    // Stale filter text must not survive a close, and the carousel should open
    // centred on the theme that is actually applied.
    ThemeState.clearQuery()
    ThemeState.reselect(ThemeState.activeSlug)
    keys.forceActiveFocus()
    panel.shown = true
  }
}
