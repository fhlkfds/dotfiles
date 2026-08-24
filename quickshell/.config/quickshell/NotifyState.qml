pragma Singleton
import Quickshell
import QtQuick
import "notifications" as Notifications

// Compatibility facade for the bar. Quickshell's notification service is the
// only owner of state; keyboard bindings and other frontends use the same IPC.
Singleton {
  id: root

  readonly property bool dnd: Notifications.NotificationService.dnd
  readonly property int count: Notifications.NotificationService.visibleCount

  // Verified by rasterising the codepoint against JetBrainsMono Nerd Font --
  // the neighbouring "bell" names in the MDI range are not the bell glyphs.
  readonly property string glyphBellOff: String.fromCodePoint(0xf0a91) // md-bell_off_outline

  function toggle() { Notifications.NotificationService.setDnd(!root.dnd) }
  function openHistory() { Notifications.NotificationService.showHistory() }
}
