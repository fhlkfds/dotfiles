import QtQuick
// Defer completion until the event loop, then read only temporary fixtures.
Item {
  id: fv
  property string path: ""
  property bool watchChanges: false
  property bool printErrors: true
  property bool preload: true
  property string _text: ""
  signal fileChanged()
  signal loaded()
  signal loadFailed(int error)
  signal adapterUpdated()
  signal saved()
  signal saveFailed(int error)
  function text() { return _text }
  // In-memory completion only: this fixture never writes outside its root.
  function setText(value) { _text = value; Qt.callLater(() => saved()) }
  function reload() { Qt.callLater(_load) }
  function writeAdapter() {}
  function _load() {
    if (path === "") return
    if (!path.startsWith(fixtureRoot + "/") && !path.startsWith("file://" + fixtureRoot + "/")) { loadFailed(3); return }
    const x = new XMLHttpRequest()
    x.open("GET", path.startsWith("file:") ? path : "file://" + path, false)
    try { x.send() } catch (e) { loadFailed(3); return }
    if (x.responseText !== "") { _text = x.responseText; loaded() } else loadFailed(3)
  }
  onPathChanged: if (preload) Qt.callLater(_load)
}
