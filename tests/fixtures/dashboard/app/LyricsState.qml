pragma Singleton
import QtQuick
QtObject {
  property string status: "synced"
  property string plainText: ""
  property int activeIndex: 3
  property var lines: [
    { ms: 0, text: "Lines that fold into the night" }, { ms: 1, text: "Every contour holds the light" },
    { ms: 2, text: "Tracing maps across the screen" }, { ms: 3, text: "Following the shapes between" },
    { ms: 4, text: "Where the gradients collide" }, { ms: 5, text: "All the dotfiles side by side" },
    { ms: 6, text: "Keep the rhythm, keep the line" }, { ms: 7, text: "Contour lines in Tokyo time" } ]
}
