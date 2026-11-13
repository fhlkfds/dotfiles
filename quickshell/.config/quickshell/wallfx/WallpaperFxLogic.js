// Pure helpers for WallpaperFx.qml, shared with tests/wallpaper-fx.logic.test.js.
// Colours are {r, g, b} in 0..1, which QML colours also satisfy.

function chroma(c) {
  return Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b)
}

function luma(c) {
  return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
}

// The most vivid colour, not the accent: an accent can be a cream that
// vanishes on a cream sky.
function mostVivid(colors) {
  return colors.reduce(function (a, b) { return chroma(b) > chroma(a) ? b : a })
}

function lightest(colors) {
  return colors.reduce(function (a, b) { return luma(b) > luma(a) ? b : a })
}

// hyprpaper's "cover": scale the image to cover the screen, centred. Returns
// the image-uv rectangle the screen sees as [x, y, w, h].
function cover(imageWidth, imageHeight, screenWidth, screenHeight) {
  var iw = Math.max(imageWidth, 1), ih = Math.max(imageHeight, 1)
  var s = Math.max(screenWidth / iw, screenHeight / ih)
  var w = screenWidth / (iw * s), h = screenHeight / (ih * s)
  return [(1 - w) / 2, (1 - h) / 2, w, h]
}

// A path as a file URL, so names with '#', '?' or '%' still load.
function fileUrl(path) {
  if (!path) return ""
  return "file://" + path.split("/").map(encodeURIComponent).join("/")
}

if (typeof module !== "undefined") {
  module.exports = { chroma: chroma, luma: luma, mostVivid: mostVivid, lightest: lightest,
                     cover: cover, fileUrl: fileUrl }
}
