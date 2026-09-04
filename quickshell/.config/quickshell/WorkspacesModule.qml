import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  spacing: root.s(4)

  // Fixed 1-10 mapping. Not derived from Hyprland.workspaces (which only
  // lists workspaces that have actually been visited this session).
  // Glyph codepoints verified against the installed "JetBrainsMono Nerd
  // Font" cmap; svg entries are bundled brand icons (icons/*.svg).
  readonly property var slots: [
    { id: 1, glyph: "" },                 // fa-terminal
    { id: 2, svg: "icons/helium.svg" },
    { id: 3, svg: "icons/obsidian.svg" },
    { id: 4, glyph: "" },                 // custom-neovim
    { id: 5, glyph: "" },                 // fa-gamepad
    { id: 6, svg: "icons/qemu.svg" },
    { id: 7, glyph: "" },                 // cod-folder
    { id: 8, glyph: "" },                 // fa-telegram
    { id: 9, glyph: "" },                 // fa-spotify
    { id: 10, glyph: "" }                 // fa-terminal
  ]

  Repeater {
    model: root.slots

    Rectangle {
      id: cell
      width: root.s(26)
      height: root.s(26)
      radius: root.s(5)
      readonly property bool isFocused: Hyprland.focusedWorkspace !== null
                                         && Hyprland.focusedWorkspace.id === modelData.id
      color: isFocused ? Theme.accent : "transparent"

      Text {
        visible: modelData.glyph !== undefined
        anchors.centerIn: parent
        text: modelData.glyph !== undefined ? modelData.glyph : ""
        font.family: Theme.glyphFamily
        font.pixelSize: root.s(15)
        color: cell.isFocused ? Theme.bgDeep : Theme.textDim
      }

      Image {
        visible: modelData.svg !== undefined
        anchors.centerIn: parent
        width: root.s(15)
        height: root.s(15)
        source: modelData.svg !== undefined ? modelData.svg : ""
        smooth: true
        opacity: cell.isFocused ? 1 : Theme.opacityInactive
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        // Hyprland 0.55+ evaluates dispatches as Lua expressions. Quickshell
        // wraps this in hl.dispatch(...), so the expression must be an
        // hl.dsp dispatcher rather than the old "workspace N" text command.
        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + modelData.id + "\" })")
      }
    }
  }
}
