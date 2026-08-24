import QtQuick
import Quickshell.Services.Notifications as QsNotifications

QsNotifications.NotificationServer {
  id: server
  required property var service

  // Preserve the native server and tracked objects across QML hot reloads.
  // The disk-backed model separately covers full process restarts.
  keepOnReload: true
  persistenceSupported: true
  bodySupported: true
  bodyMarkupSupported: false
  bodyHyperlinksSupported: false
  bodyImagesSupported: false
  actionsSupported: true
  actionIconsSupported: false
  imageSupported: true
  inlineReplySupported: false

  onNotification: function(notification) {
    server.service.receive(notification)
  }
}
