pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// A miniature of the desktop a theme produces, drawn entirely from that theme's
// own palette.
//
// This is a FIXED design-space component: it always lays itself out at
// designW x designH and is squeezed to whatever box the carousel needs by the
// caller's transform. One component therefore serves both the 768-wide centre
// and the 108-wide slices -- squeezing it is exactly the foreshortened smear a
// rotated cover-flow card should look like, and animating the target box is
// what produces the collapse/expand transition.
//
// Nothing here reads the Theme singleton: colours come from `entry`, the row out
// of `theme index --json`. That is what stops focusing a tile from recolouring
// the picker around it.
//
// No Process, no thumbnail generation, no cache. The only I/O is the wallpaper
// Image, which is asynchronous, downscaled on load and gated by `loadImage`.
Item {
  id: root

  // A row from ThemeState.themes. Named `entry` rather than `palette` because
  // QQuickItem already has a `palette` property and shadowing it is a trap.
  required property var entry
  // Painted at full brightness with a heavier border when true.
  property bool selected: false
  // The theme currently applied to the desktop -- independent of selection.
  property bool isActive: false
  // Set false for far-away slices so their wallpaper is never fetched.
  property bool loadImage: true

  readonly property real designW: Theme.coverSelectedW
  readonly property real designH: Theme.coverSelectedH

  implicitWidth: root.designW
  implicitHeight: root.designH
  width: root.designW
  height: root.designH

  readonly property var colors: root.entry && root.entry.colors ? root.entry.colors : ({})
  readonly property var style: root.entry && root.entry.style ? root.entry.style : ({})
  readonly property string wallpaper:
    root.entry && root.entry.wallpaper ? root.entry.wallpaper : ""

  // Every colour goes through here, so a theme missing a key renders in a
  // fallback rather than as a transparent hole.
  function c(key, fallback) {
    const v = root.colors[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  function n(key, fallback) {
    const v = root.style[key]
    return typeof v === "number" ? v : fallback
  }

  // The preview carries the theme's own corner treatment, so a square theme
  // like Lumon looks square before you apply it.
  readonly property real innerRadius: Math.max(2, root.n("rounding", 8) * 1.4)

  readonly property string userName: {
    const u = Quickshell.env("USER")
    return (u && u.length > 0) ? u : "user"
  }

  // Design-space type scale. Legible at 768 wide; an unreadable smear at 108,
  // which is correct for a slice.
  readonly property real fontBody: 13
  readonly property real fontSmall: 11

  clip: true

  // ── ground ─────────────────────────────────────────────────────────────────
  // Always painted, so a theme with no wallpaper (12 of 23) or a wallpaper that
  // fails to decode still reads as a desktop rather than a hole.
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: root.c("background", "#1a1a1a") }
      GradientStop { position: 1.0; color: root.c("surface", "#242424") }
    }
  }

  Image {
    id: wall
    anchors.fill: parent
    source: (root.loadImage && root.wallpaper !== "") ? "file://" + root.wallpaper : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    // Downscaled at load: a slice is ~108px, the centre ~768px, so full-size
    // wallpapers are never held in memory.
    sourceSize.width: Math.round(root.designW)
    visible: status === Image.Ready
    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
      NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
  }

  // ── Waybar ─────────────────────────────────────────────────────────────────
  Rectangle {
    id: bar
    width: parent.width
    height: 30
    color: root.c("backgroundAlt", "#101010")
    opacity: 0.97

    Row {
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      // Workspace pills: one active in the accent, the rest muted. The same
      // mapping the real bar uses.
      Repeater {
        model: 5
        Rectangle {
          required property int index
          width: index === 1 ? 26 : 14
          height: 14
          radius: Math.min(7, root.innerRadius)
          color: index === 1 ? root.c("accent", "#888888") : root.c("muted", "#666666")
          opacity: index === 1 ? 1.0 : 0.5
        }
      }
    }

    Text {
      anchors.centerIn: parent
      text: "  " + root.entryName
      color: root.c("foreground", "#cccccc")
      font.family: Theme.uiFamily
      font.pixelSize: root.fontSmall
      opacity: 0.75
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Text {
        text: "42%"
        color: root.c("cyan", "#88cccc")
        font.family: Theme.uiFamily
        font.pixelSize: root.fontSmall
      }
      Text {
        text: "09:41"
        color: root.c("foregroundBright", "#eeeeee")
        font.family: Theme.uiFamily
        font.pixelSize: root.fontSmall
        font.bold: true
      }
    }
  }

  readonly property string entryName: root.entry && root.entry.name ? root.entry.name : ""

  // ── Kitty ──────────────────────────────────────────────────────────────────
  Rectangle {
    id: term
    x: 46
    y: bar.height + 54
    width: 372
    height: 226
    radius: root.innerRadius
    color: root.c("background", "#1a1a1a")
    opacity: 0.94
    border.width: 1
    border.color: root.c("border", "#333333")

    // Title bar
    Rectangle {
      id: termTitle
      width: parent.width
      height: 22
      radius: root.innerRadius
      color: root.c("surface", "#242424")

      // Square off the bottom corners so the title meets the body flush.
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.radius
        color: parent.color
      }

      Text {
        anchors.centerIn: parent
        text: "kitty"
        color: root.c("muted", "#888888")
        font.family: Theme.uiFamily
        font.pixelSize: root.fontSmall
      }
    }

    Column {
      x: 12
      y: termTitle.height + 10
      spacing: 5

      Row {
        spacing: 6
        Text {
          text: root.userName + "@arch"
          color: root.c("green", "#88bb88")
          font.family: Theme.glyphFamily
          font.pixelSize: root.fontBody
          font.bold: true
        }
        Text {
          text: "~/dotfiles"
          color: root.c("accent", "#8888bb")
          font.family: Theme.glyphFamily
          font.pixelSize: root.fontBody
          font.bold: true
        }
      }

      Row {
        spacing: 6
        Text {
          text: "❯"
          color: root.c("accent", "#8888bb")
          font.family: Theme.glyphFamily
          font.pixelSize: root.fontBody
        }
        Text {
          text: "theme set " + (root.entry && root.entry.slug ? root.entry.slug : "…")
          color: root.c("foregroundBright", "#eeeeee")
          font.family: Theme.glyphFamily
          font.pixelSize: root.fontBody
        }
      }

      Text {
        text: "  ok    applied " + root.entryName
        color: root.c("green", "#88bb88")
        font.family: Theme.glyphFamily
        font.pixelSize: root.fontBody
      }
      Text {
        text: "  warn  12 themes have no wallpaper"
        color: root.c("yellow", "#bbbb88")
        font.family: Theme.glyphFamily
        font.pixelSize: root.fontBody
      }
      Text {
        text: "  error nothing broke today"
        color: root.c("red", "#bb8888")
        font.family: Theme.glyphFamily
        font.pixelSize: root.fontBody
      }
      Text {
        text: "❯ "
        color: root.c("accent", "#8888bb")
        font.family: Theme.glyphFamily
        font.pixelSize: root.fontBody
      }
    }
  }

  // ── Rofi ───────────────────────────────────────────────────────────────────
  Rectangle {
    x: 462
    y: bar.height + 92
    width: 250
    height: 158
    radius: root.innerRadius
    color: root.c("background", "#1a1a1a")
    opacity: 0.93
    border.width: 1
    border.color: root.c("borderActive", root.c("accent", "#8888bb"))

    Column {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 7

      // input plate
      Rectangle {
        width: parent.width
        height: 26
        radius: Math.min(root.innerRadius, 8)
        color: root.c("surface", "#242424")

        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: 8
          text: "❯ search…"
          color: root.c("muted", "#888888")
          font.family: Theme.uiFamily
          font.pixelSize: root.fontSmall
        }
      }

      // selected row, then two normal rows
      Rectangle {
        width: parent.width
        height: 22
        radius: Math.min(root.innerRadius, 8)
        color: root.c("accent", "#8888bb")
        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: 8
          text: "Files"
          color: root.c("onAccent", "#111111")
          font.family: Theme.uiFamily
          font.pixelSize: root.fontSmall
          font.bold: true
        }
      }
      Repeater {
        model: ["Terminal", "Browser"]
        Text {
          required property var modelData
          leftPadding: 8
          text: modelData
          color: root.c("foreground", "#cccccc")
          font.family: Theme.uiFamily
          font.pixelSize: root.fontSmall
        }
      }
    }
  }

  // ── Quickshell panel hint ──────────────────────────────────────────────────
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height - height - 22
    width: 320
    height: 40
    radius: root.innerRadius
    color: root.c("surface", "#242424")
    opacity: 0.9
    border.width: 1
    border.color: root.c("border", "#333333")

    Row {
      anchors.centerIn: parent
      spacing: 16

      Repeater {
        model: [root.c("accent", "#8888bb"), root.c("cyan", "#88cccc"),
                root.c("green", "#88bb88"), root.c("yellow", "#bbbb88"),
                root.c("magenta", "#bb88bb")]
        Rectangle {
          required property var modelData
          width: 18
          height: 18
          radius: Math.min(9, root.innerRadius)
          color: modelData
        }
      }
    }
  }
}
