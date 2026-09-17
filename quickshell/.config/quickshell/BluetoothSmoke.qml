import Quickshell
import QtQuick

// Headless parse/instantiation and logic harness for the Bluetooth menu.
// The popup window itself is only compiled, not constructed: PopupWindow needs
// a live compositor. Run with:
//   QT_QPA_PLATFORM=offscreen quickshell -p BluetoothSmoke.qml
//
// Quickshell has no API for setting an exit code, so the result is reported on
// stdout: tests/bluetooth-control.test.sh requires the final "ok:" line and
// rejects any "FAIL" line.
Scope {
  id: smoke

  readonly property var state: BluetoothState
  BluetoothIcon { screenName: "smoke" }
  Component { BluetoothPanel { ownerScreen: "smoke" } }

  // Quitting from Component.onCompleted is ignored while the engine is still
  // loading, so the harness tears itself down from a timer like the other
  // *Smoke.qml files do.
  Timer {
    interval: 250
    running: true
    onTriggered: Qt.quit()
  }

  property int failures: 0

  function check(name, condition) {
    if (condition) {
      console.log("ok   " + name)
    } else {
      console.log("FAIL " + name)
      smoke.failures += 1
    }
  }

  function raw(address, name, paired, connected) {
    return { address: address, name: name, paired: paired,
             connected: connected, trusted: false, icon: "", battery: null }
  }

  Component.onCompleted: {
    const s = BluetoothState

    // --- normalise -----------------------------------------------------------
    const n = s.normalise({ address: "AA:BB:CC:DD:EE:01", name: "Pad",
                            paired: true, connected: false, battery: null })
    check("normalise maps a null battery to -1", n.battery === -1)
    check("normalise defaults a missing icon to an empty string", n.icon === "")
    check("normalise coerces flags to booleans",
          n.paired === true && n.connected === false && n.trusted === false)
    const withBattery = s.normalise({ address: "A", name: "B", battery: 87.4 })
    check("normalise rounds a battery reading", withBattery.battery === 87)

    // --- ordering ------------------------------------------------------------
    const unsorted = [
      s.normalise(smoke.raw("AA:BB:CC:DD:EE:04", "zeta pad", false, false)),
      s.normalise(smoke.raw("AA:BB:CC:DD:EE:02", "beta keys", true, false)),
      s.normalise(smoke.raw("AA:BB:CC:DD:EE:03", "alpha buds", true, true)),
      s.normalise(smoke.raw("AA:BB:CC:DD:EE:01", "Alpha mouse", true, true))
    ]
    const sorted = s.sortDevices(unsorted)
    check("connected devices sort first",
          sorted[0].connected && sorted[1].connected)
    check("connected devices sort alphabetically, case-insensitively",
          sorted[0].name === "alpha buds" && sorted[1].name === "Alpha mouse")
    check("paired devices sort above merely discovered ones",
          sorted[2].name === "beta keys" && sorted[3].name === "zeta pad")
    check("sorting does not mutate its input", unsorted[0].name === "zeta pad")

    // --- incremental model sync ---------------------------------------------
    //
    // syncInto is exercised directly on one model: it is the diffing engine,
    // and syncModel below is only the zone split layered on top of it.
    s.syncInto(s.paired, sorted)
    check("sync populates the model", s.paired.count === 4)
    check("sync preserves order", s.paired.get(0).address === "AA:BB:CC:DD:EE:03")

    // A poll where only one battery moved must leave every other row alone.
    const bumped = sorted.map(d => ({
      address: d.address, name: d.name, paired: d.paired,
      connected: d.connected, trusted: d.trusted, icon: d.icon,
      battery: d.address === "AA:BB:CC:DD:EE:01" ? 42 : d.battery
    }))
    s.syncInto(s.paired, bumped)
    check("sync updates a changed role in place",
          s.paired.count === 4 && s.paired.get(1).battery === 42)
    check("sync leaves untouched rows untouched", s.paired.get(0).battery === -1)

    // Reorder: the mouse disconnects and drops into the paired group.
    const reordered = s.sortDevices(bumped.map(d => ({
      address: d.address, name: d.name, paired: d.paired,
      connected: d.address === "AA:BB:CC:DD:EE:01" ? false : d.connected,
      trusted: d.trusted, icon: d.icon, battery: d.battery
    })))
    s.syncInto(s.paired, reordered)
    check("sync reorders rather than rebuilding", s.paired.count === 4)
    check("a disconnected device drops below the connected group",
          s.paired.get(0).address === "AA:BB:CC:DD:EE:03"
          && s.paired.get(1).address === "AA:BB:CC:DD:EE:01"
          && s.paired.get(1).connected === false)

    // Removal.
    s.syncInto(s.paired, reordered.slice(0, 2))
    check("sync removes rows that left the poll", s.paired.count === 2)

    // --- zone split ----------------------------------------------------------
    //
    // The panel renders three zones, so a poll is split into three models and
    // a device lands in exactly one of them: connected, paired-and-idle, or
    // merely discovered.
    s.syncModel(reordered)
    check("connected devices land in the hero zone",
          s.connected.count === 1
          && s.connected.get(0).address === "AA:BB:CC:DD:EE:03")
    check("paired but idle devices land in the device list", s.paired.count === 2)
    check("unpaired devices land in discovery",
          s.discovered.count === 1
          && s.discovered.get(0).address === "AA:BB:CC:DD:EE:04")
    check("a paired device never appears in discovery", s.discoveredCount === 1)

    // Connecting the mouse moves it out of the paired zone and into the hero.
    const connectedMouse = s.sortDevices(reordered.map(d => ({
      address: d.address, name: d.name, paired: d.paired,
      connected: d.address === "AA:BB:CC:DD:EE:01" ? true : d.connected,
      trusted: d.trusted, icon: d.icon, battery: d.battery
    })))
    s.syncModel(connectedMouse)
    check("a device that connects moves into the hero zone",
          s.connected.count === 2 && s.paired.count === 1)
    s.syncModel(reordered)
    check("a device that disconnects moves back into the device list",
          s.connected.count === 1 && s.paired.count === 2)

    // --- action labels -------------------------------------------------------
    check("a queued action reads as a progress label",
          s.actionLabel("connect") === "Connecting"
          && s.actionLabel("forget") === "Removing")
    check("an unknown action falls back to its own name",
          s.actionLabel("nonsense") === "nonsense")

    // --- primary action ------------------------------------------------------
    check("a connected device disconnects",
          s.primaryAction({ connected: true, paired: true }) === "disconnect")
    check("a paired device connects",
          s.primaryAction({ connected: false, paired: true }) === "connect")
    check("an unpaired device pairs",
          s.primaryAction({ connected: false, paired: false }) === "pair")

    // --- pending state -------------------------------------------------------
    check("nothing is pending initially", s.pendingFor("AA:BB:CC:DD:EE:01") === "")
    s.pending = { "AA:BB:CC:DD:EE:01": "connect", "": "power" }
    check("a pending device action is reported",
          s.pendingFor("AA:BB:CC:DD:EE:01") === "connect")
    check("an unrelated device stays free",
          s.pendingFor("AA:BB:CC:DD:EE:03") === "")
    check("adapter-wide actions are tracked separately", s.adapterBusy === true)
    s.clearPending("AA:BB:CC:DD:EE:01")
    check("clearing one action leaves the others",
          s.pendingFor("AA:BB:CC:DD:EE:01") === "" && s.adapterBusy === true)
    s.clearPending("")
    check("clearing the adapter action frees the adapter", s.adapterBusy === false)

    // --- glyphs --------------------------------------------------------------
    check("a known device class gets its own glyph",
          s.glyphForDevice({ icon: "input-mouse" }) !== s.glyphOn)
    check("an unknown device class falls back to the bluetooth glyph",
          s.glyphForDevice({ icon: "nonsense" }) === s.glyphOn)
    check("a missing device falls back to the bluetooth glyph",
          s.glyphForDevice(null) === s.glyphOn)

    // --- error routing -------------------------------------------------------
    //
    // A failed connect belongs on the row that failed; adapter and poll
    // failures belong in the header banner. The panel tells them apart by
    // errorAddress, so enqueueing anything must clear the previous failure.
    s.lastError = "Could not connect"
    s.errorAddress = "AA:BB:CC:DD:EE:01"
    check("a device failure is attributed to its device",
          s.errorAddress === "AA:BB:CC:DD:EE:01")
    s.enqueue("trust", "AA:BB:CC:DD:EE:01")
    check("a new action clears the previous failure",
          s.lastError === "" && s.errorAddress === "")
    s.clearPending("AA:BB:CC:DD:EE:01")

    console.log(smoke.failures === 0
      ? "ok: BluetoothState logic"
      : ("FAIL: " + smoke.failures + " assertion(s) failed"))
  }
}
