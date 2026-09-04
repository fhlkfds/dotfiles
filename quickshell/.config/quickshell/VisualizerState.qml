pragma Singleton
import Quickshell
import QtQuick

Singleton {
  property bool visible: false

  function toggle() {
    visible = !visible
  }
}
