import Quickshell
import QtQuick
import QtQuick.Window

// Headless harness for the desktop vitals card. Stand-in metrics replace
// SysState and BatteryState, so it never reads the real sensors.
//
// With VITALS_SHOT set to a directory it also renders vitals.png over
// VITALS_WALLPAPER, for previews. Rendering is offscreen.
Scope {
  id: smoke
  property int failures: 0

  readonly property string shotDir: Quickshell.env("VITALS_SHOT") || ""
  readonly property string wallpaper: Quickshell.env("VITALS_WALLPAPER") || ""

  QtObject {
    id: fakeSys
    property string cpuModel: "AMD Ryzen 9 5900X 12-Core Processor"
    property real cpuPercent: 18.4
    property bool cpuSeeded: true
    property real memUsedBytes: 12.8 * 1024 * 1024 * 1024
    property real memTotalBytes: 32 * 1024 * 1024 * 1024
    property real diskUsedBytes: 300 * 1024 * 1024 * 1024
    property real diskTotalBytes: 1000 * 1024 * 1024 * 1024
    property bool cpuTempAvailable: true
    property real cpuTempC: 48
    readonly property real cpuTempF: cpuTempC * 9 / 5 + 32
    property real uptimeSeconds: 3 * 3600 + 12 * 60
    property bool mouseBatteryAvailable: true
    property real mouseBatteryPercent: 82
    property bool mouseCharging: false
    readonly property real memFraction: memTotalBytes > 0 ? memUsedBytes / memTotalBytes : 0
    readonly property real diskFraction: diskTotalBytes > 0 ? diskUsedBytes / diskTotalBytes : 0
    function fmtBytes(b) { return SysState.fmtBytes(b) }
    function fmtUptime(s) { return SysState.fmtUptime(s) }
  }

  QtObject {
    id: fakeBattery
    property bool hasBattery: false
    property int percent: 0
    property bool charging: false
  }

  Item {
    id: host
    visible: true
    DesktopVitalsCard { id: card; sys: fakeSys; battery: fakeBattery }
  }

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++smoke.failures }
  }

  function findText(item, wanted) {
    if (item.text !== undefined && item.visible !== false && String(item.text) === wanted)
      return true
    for (let i = 0; i < item.children.length; i++)
      if (findText(item.children[i], wanted))
        return true
    return false
  }

  function findAll(item, predicate, out) {
    if (predicate(item))
      out.push(item)
    for (let i = 0; i < item.children.length; i++)
      findAll(item.children[i], predicate, out)
    return out
  }

  // Switching themes rewrites theme.json and Theme reloads it, so the card
  // must take every colour from Theme bindings rather than copies. Swap in a
  // palette built from the current one's own colours, rotated, and check the
  // slab, the title, the text and the rings all follow.
  function checkThemeSwap() {
    const before = Theme.themeData
    const rings = () => findAll(card, i => i.fill !== undefined && i.track !== undefined, [])
    const title = () => findAll(card, i => i.text === "VITALS", [])[0]
    const swapped = {
      background: String(Theme.foregroundBright),
      foregroundBright: String(Theme.background),
      foreground: String(Theme.backgroundAlt),
      accent: String(Theme.critical),
      critical: String(Theme.accent),
    }
    Theme.themeData = { colors: swapped }

    check("theme swap reaches Theme", Qt.colorEqual(Theme.accent, swapped.accent))
    check("slab follows the theme background",
      Qt.colorEqual(Qt.rgba(card.children[0].color.r, card.children[0].color.g, card.children[0].color.b, 1),
        swapped.background))
    check("title follows the theme accent", Qt.colorEqual(title().color, swapped.accent))
    const ringText = findAll(card, i => i.text === "18%" && i.font !== undefined, [])
    check("ring text follows the theme foreground",
      ringText.length > 0 && ringText.every(t => Qt.colorEqual(t.color, swapped.foregroundBright)))
    const cpuRing = rings()[0]
    check("rings repaint in the new accent", Qt.colorEqual(cpuRing.fill, swapped.accent))
    check("ring tracks follow the theme foreground",
      Qt.colorEqual(Qt.rgba(cpuRing.track.r, cpuRing.track.g, cpuRing.track.b, 1), swapped.foreground))

    Theme.themeData = before
    check("restoring the theme restores the card", Qt.colorEqual(title().color, Theme.accent)
      && Qt.colorEqual(rings()[0].fill, Theme.accent))
  }

  Component.onCompleted: {
    check("card has a real size", card.implicitWidth > card.gaugeSize * 5 && card.implicitHeight > card.gaugeSize)
    check("cpu name is shortened", card.cpuName === "Ryzen 9 5900X")
    check("cpu ring shows the load", findText(card, "18%"))
    check("ram ring shows the used share", findText(card, "40%"))
    check("disk ring shows the used share", findText(card, "30%"))
    check("temperature shows in fahrenheit", findText(card, "118°F"))
    check("free ram is spelled out", findText(card, "19 GB") && findText(card, "RAM free"))
    check("free disk is spelled out", findText(card, "700 GB") && findText(card, "disk free"))
    check("uptime is shown", findText(card, "up 3h 12m"))

    check("mouse battery stands in on a desktop", card.batteryShown && card.batteryLabel === "MOUSE"
      && findText(card, "82%"))
    fakeBattery.hasBattery = true
    fakeBattery.percent = 64
    check("a system battery wins over the mouse", card.batteryLabel === "BATTERY" && findText(card, "64%"))
    fakeBattery.hasBattery = false
    fakeSys.mouseBatteryAvailable = false
    check("no battery means no battery ring", !card.batteryShown && !findText(card, "MOUSE"))
    fakeSys.mouseBatteryAvailable = true

    check("load is accent while comfortable", Qt.colorEqual(card.loadColor(0.4), Theme.accent))
    check("load warns when high", Qt.colorEqual(card.loadColor(0.8), Theme.warning))
    check("load goes critical near full", Qt.colorEqual(card.loadColor(0.95), Theme.critical))
    check("hot cpu goes critical", Qt.colorEqual(card.tempColor(88), Theme.critical))
    check("low battery goes critical", Qt.colorEqual(card.batteryColor(10, false), Theme.critical))
    check("charging battery is green", Qt.colorEqual(card.batteryColor(10, true), Theme.success))

    fakeSys.cpuSeeded = false
    check("cpu shows n/a until the first delta", findText(card, "n/a"))
    fakeSys.cpuSeeded = true

    checkThemeSwap()

    if (smoke.failures === 0)
      console.log("ok: Desktop vitals card")

    if (smoke.shotDir === "")
      quitTimer.start()
  }

  // --- optional preview render -----------------------------------------------

  Variants {
    model: smoke.shotDir === "" ? [] : [1]

    Window {
      id: shotWindow
      required property var modelData
      width: shotCard.implicitWidth + Theme.fs(80)
      height: shotCard.implicitHeight + Theme.fs(80)
      visible: true
      color: "black"

      Image {
        anchors.fill: parent
        source: smoke.wallpaper === "" ? "" : "file://" + smoke.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
      }

      DesktopVitalsCard {
        id: shotCard
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        sys: fakeSys
        battery: fakeBattery
      }

      Timer {
        interval: 800
        running: true
        onTriggered: shotWindow.contentItem.grabToImage(function (result) {
          const path = smoke.shotDir + "/vitals.png"
          console.log(result.saveToFile(path) ? "shot " + path : "FAIL shot " + path)
          quitTimer.start()
        })
      }
    }
  }

  Timer { id: quitTimer; interval: 100; onTriggered: Qt.quit() }
}
