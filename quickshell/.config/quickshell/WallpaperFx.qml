// WallpaperFx.qml: the wallpaper transitions, drawn by the shell over hyprpaper.
// Adapted from diegoMalagrida/pocket-dots (home/.config/quickshell/WallpaperFx.qml, GPL-3.0).
//
// Two transitions, in a shader (shaders/wallfx.frag) fed by the maps of
// ~/.local/bin/wallfx:
//
//   contagion  colonies landing at random places eat through the old wallpaper
//              in crisp 4 px cells, each burning for an instant in the theme's
//              most vivid colour.
//   outline    when the new wallpaper has a character: a thin quiet line draws
//              its outline, it fills in, and the rest spreads out of it.
//
// HOW IT HANDS OVER WITH HYPRPAPER. hyprpaper stays the wallpaper; this draws
// only for the length of a change, on the Bottom layer: hyprpaper rebuilds its
// Background surface on every change, which would land on top of anything else
// there. The windows stay mapped and draw nothing while idle, and shell.qml
// creates them before the desktop widgets, which therefore stay above them.
// The order is what makes it seamless:
//   1. load both images and the maps, off the main thread;
//   2. start the transition and, at the same time, fade in over hyprpaper. At
//      t≈0 the transition IS the old wallpaper, so nobody sees the fade;
//   3. once fully covered, switch hyprpaper underneath;
//   4. the transition ends on the new image, which hyprpaper now shows too;
//   5. fade out, and the textures are released.
// If anything fails to load within 2.5 s, hyprpaper switches on its own: the
// wallpaper must change even if the effect cannot be shown.
//
// IPC (hypr-wallpaper-picker calls it; `wallfx pick` chooses the kind and maps):
//   quickshell ipc call wallfx play OLD NEW contagion|outline MAP LINE
import Quickshell
import Quickshell.Wayland
import QtQuick

Scope {
  WallpaperFxState {
    id: fxState
    screenCount: screens.instances.length
  }

  Variants {
    id: screens
    model: Quickshell.screens.filter(s => !fxState.onlyScreen || s.name === fxState.onlyScreen)

    PanelWindow {
      required property var modelData
      screen: modelData
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region {}                       // clicks go through to the desktop
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "quickshell-wallfx"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      WallpaperFxContent {
        anchors.fill: parent
        fx: fxState
      }
    }
  }
}
