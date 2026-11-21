import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtTest

// Verification harness, staged into a copy of the shell by `verify shot`.
// Draws the real BatteryIcon, clicks it with a synthesized mouse event (the
// user's path to the panel), then saves the panel that opened as a PNG. The
// device and power profiles are fakes, so nothing reads UPower or switches
// the machine's real profile.
Scope {
  id: shot
  property int failures: 0
  property int step: 0
  readonly property string outDir: Quickshell.env("VERIFY_SHOT_DIR")
  readonly property var steps: [
    { name: "discharging", percentage: 0.54, state: UPowerDeviceState.Discharging, rate: 13.3 },
    { name: "charging", percentage: 0.81, state: UPowerDeviceState.Charging, rate: 21.7 },
    { name: "critical", percentage: 0.07, state: UPowerDeviceState.Discharging, rate: 9.8 }
  ]
  property var panel: null

  QtObject { id: device; property bool ready: true; property bool isLaptopBattery: true; property bool isPresent: true; property int type: UPowerDeviceType.Battery; property real percentage: 0.54; property int state: UPowerDeviceState.Discharging; property real timeToEmpty: 5400; property real timeToFull: 2700; property real energy: 26.2; property real energyCapacity: 48.5; property real changeRate: 13.3 }
  QtObject { id: fakeProfiles; property int profile: PowerProfile.Balanced; property bool hasPerformanceProfile: true }

  function check(name, condition) { if (condition) console.log("ok   " + name); else { console.log("FAIL " + name); ++shot.failures } }

  function findPanel(item) {
    for (let i = 0; i < item.data.length; ++i) {
      const child = item.data[i]
      if (child && child.anchorItem !== undefined && child.implicitWidth !== undefined && child.visible !== undefined && child.toString().indexOf("BatteryPanel") === 0)
        return child
    }
    return null
  }

  function findContent(node) {
    if (!node) return null
    if (node.profiles !== undefined && node.supplyLine !== undefined) return node
    const kids = node.children || []
    for (let i = 0; i < kids.length; ++i) { const hit = findContent(kids[i]); if (hit) return hit }
    return null
  }

  // A Quickshell window, not a plain QtQuick Window: PopupWindow only opens
  // over a Quickshell parent, so a plain Window leaves the panel closed.
  FloatingWindow {
    id: barWindow
    implicitWidth: 240; implicitHeight: 48; visible: true
    color: "transparent"
    // grabToImage needs an item the QML engine owns; a window's contentItem
    // is not one, so the strip is grabbed through this rectangle.
    Rectangle {
      id: barStrip
      anchors.fill: parent
      color: Theme.bg
      BatteryIcon { id: icon; anchors.centerIn: parent; barScale: 1.25 }
    }
  }

  TestEvent { id: input }

  Component.onCompleted: {
    BatteryState.deviceOverride = device
    BatteryState.refresh()
    shot.panel = findPanel(icon)
    check("battery panel is attached to the bar icon", shot.panel !== null)
    check("panel starts closed", shot.panel !== null && !shot.panel.visible)
    startTimer.start()
  }

  Timer { id: startTimer; interval: 300; onTriggered: shot.applyStep() }

  function applyStep() {
    const s = shot.steps[shot.step]
    device.percentage = s.percentage; device.state = s.state; device.changeRate = s.rate
    BatteryState.refresh()
    if (shot.step === 0) {
      // Left click in the icon's centre, the same event a user's click delivers.
      input.mouseClick(icon, icon.width / 2, icon.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
      check("clicking the bar icon opens the panel", shot.panel !== null && shot.panel.visible)
    }
    grabTimer.start()
  }

  Timer {
    id: grabTimer
    interval: 600
    onTriggered: {
      const s = shot.steps[shot.step]
      const content = shot.findContent(shot.panel ? shot.panel.contentItem : null)
      if (content) {
        content.profiles = fakeProfiles
        console.log("text " + s.name + ": " + content.percentText + " | " + content.supplyLine + " | " + content.powerPrimary + " " + content.powerSecondary + " | " + content.chargePrimary + " " + content.chargeSecondary)
      }
      check(s.name + ": panel content is reachable", content !== null)
      const iconPath = shot.outDir + "/battery-icon-" + s.name + ".png"
      barStrip.grabToImage(function (iconImage) {
        check(s.name + ": icon saved " + iconPath, iconImage.saveToFile(iconPath))
        const panelPath = shot.outDir + "/battery-panel-" + s.name + ".png"
        // The panel's own background Rectangle (BatteryPanel.qml), for the
        // same engine-ownership reason as barStrip.
        shot.panel.contentItem.children[0].grabToImage(function (panelImage) {
          check(s.name + ": panel saved " + panelPath, panelImage.saveToFile(panelPath))
          if (++shot.step < shot.steps.length) shot.applyStep()
          else shot.finish()
        })
      })
    }
  }

  function finish() {
    input.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
    closeTimer.start()
  }

  Timer {
    id: closeTimer
    interval: 200
    onTriggered: {
      check("Escape closes the panel", shot.panel !== null && !shot.panel.visible)
      console.log(shot.failures === 0 ? "ok: battery panel shots" : ("FAIL: " + shot.failures + " shot check(s) failed"))
      Qt.quit()
    }
  }

  Timer { interval: 15000; running: true; onTriggered: { console.log("FAIL battery panel shot timed out"); Qt.quit() } }
}
