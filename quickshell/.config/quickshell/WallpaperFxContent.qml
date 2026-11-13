// WallpaperFxContent.qml: one screen's images and shader for WallpaperFx.qml.
// Takes the state as `fx`, so WallpaperFxSmoke.qml can host it in a plain window.
import QtQuick
import "wallfx/WallpaperFxLogic.js" as Fx

Item {
  id: content
  required property var fx

  readonly property bool loaded: oldImg.status === Image.Ready && newImg.status === Image.Ready
    && fieldImg.status === Image.Ready && lineImg.status === Image.Ready
  onLoadedChanged: if (loaded) content.fx.screenReady()

  // Decoded at the size of the screen (covering it), not of the file: a
  // 6 MB wallpaper does not need 24 MB of texture.
  Image { id: oldImg; visible: false; asynchronous: true; cache: false
    source: Fx.fileUrl(content.fx.oldPath)
    sourceSize: Qt.size(content.width, content.height); fillMode: Image.PreserveAspectCrop }
  Image { id: newImg; visible: false; asynchronous: true; cache: false
    source: Fx.fileUrl(content.fx.newPath)
    sourceSize: Qt.size(content.width, content.height); fillMode: Image.PreserveAspectCrop }
  // The maps hold numbers, not colours: contagion's are read texel by
  // texel (no filtering), the outline's are interpolated on purpose.
  Image { id: fieldImg; visible: false; asynchronous: true; cache: false
    smooth: content.fx.kind === "outline"
    source: Fx.fileUrl(content.fx.fieldPath) }
  Image { id: lineImg; visible: false; asynchronous: true; cache: false
    source: Fx.fileUrl(content.fx.linePath) }

  function cover(img) {
    const r = Fx.cover(img.implicitWidth, img.implicitHeight, content.width, content.height)
    return Qt.vector4d(r[0], r[1], r[2], r[3])
  }

  ShaderEffect {
    anchors.fill: parent
    visible: content.fx.active && content.loaded
    opacity: content.fx.fade
    property var oldTex: oldImg
    property var newTex: newImg
    property var fieldTex: fieldImg
    property var lineTex: lineImg
    property real t: content.fx.t
    property real mode: content.fx.kind === "outline" ? 1 : 0
    property real sw: content.width
    property real sh: content.height
    property real fw: Math.max(fieldImg.implicitWidth, 1)
    property real fh: Math.max(fieldImg.implicitHeight, 1)
    property real lw: Math.max(lineImg.implicitWidth, 1)
    property real lh: Math.max(lineImg.implicitHeight, 1)
    property real glow: content.fx.glow
    property real lineW: content.fx.lineW
    property real sdRange: 16
    property real seed: content.fx.seed
    property vector4d cropOld: content.cover(oldImg)
    property vector4d cropNew: content.cover(newImg)
    property color ember: content.fx.ember
    property color ink: content.fx.ink
    // Versioned name: Qt caches compiled shaders by URL.
    fragmentShader: Qt.resolvedUrl("shaders/wallfx.v1.frag.qsb")
  }
}
