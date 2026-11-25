pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "TimerLogic.js" as TimerLogic

Singleton {
  id: root

  property var presets: TimerLogic.DEFAULT_PRESETS
  property string sound: TimerLogic.DEFAULT_SOUND

  function apply(text) {
    let raw = null
    try { raw = JSON.parse(text) } catch (error) { console.warn("timer: config.json is not valid JSON; using defaults") }
    const values = TimerLogic.normalizeConfig(raw)
    root.presets = values.presets
    root.sound = values.sound
  }

  FileView {
    id: configFile
    path: Qt.resolvedUrl("config.json")
    blockLoading: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
  }

  Component.onCompleted: apply(configFile.text())
}
