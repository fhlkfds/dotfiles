import QtQuick
import Quickshell

// Headless check that the workspaces module draws one numbered badge per
// occupied or focused workspace from injected stand-in workspaces (no
// Hyprland needed).
FloatingWindow {
  id: window
  implicitWidth: 600
  implicitHeight: 60

  property var fakeWorkspaces: []
  property var fakeFocus: 1
  function fake(id, windows) {
    return { id: id, toplevels: { values: new Array(windows).fill({}) } }
  }

  WorkspacesModule {
    id: module
    workspaceList: window.fakeWorkspaces
    focusedWorkspaceId: window.fakeFocus
  }

  Component.onCompleted: {
    let failures = 0
    function check(label, ok) {
      if (ok) console.log("ok   " + label)
      else { failures++; console.log("FAIL " + label) }
    }
    // What is actually drawn: the text of every cell, left to right.
    function badges() {
      const out = []
      for (let i = 0; i < module.cellRepeater.count; i++) {
        const cell = module.cellRepeater.itemAt(i)
        for (let c = 0; c < cell.children.length; c++)
          if (cell.children[c].font !== undefined) out.push(cell.children[c].text)
      }
      return out.join(",")
    }

    window.fakeWorkspaces = [1, 2, 3, 4, 6, 7, 9, 11, 17].map(id => fake(id, 1))
    check("every occupied workspace shows its number: " + badges(), badges() === "1,2,3,4,6,7,9,11,17")
    check("two-digit ids render in full", badges().indexOf("11") >= 0 && badges().indexOf("17") >= 0)
    check("focused cell is the accent pill", module.cellRepeater.itemAt(0).color.toString() === Theme.accent.toString())
    check("unfocused cell paints no background", module.cellRepeater.itemAt(1).color.a === 0)

    window.fakeFocus = 17
    check("focus moves the pill", module.cellRepeater.itemAt(8).color.toString() === Theme.accent.toString()
          && module.cellRepeater.itemAt(0).color.a === 0)

    window.fakeFocus = 5
    check("focused empty workspace gets a badge", badges() === "1,2,3,4,5,6,7,9,11,17")

    window.fakeFocus = 1
    window.fakeWorkspaces = [fake(1, 1), fake(2, 0), fake(11, 0)]
    check("closing the last window removes the badge", badges() === "1")

    window.fakeWorkspaces = [fake(1, 1), fake(14, 1)]
    check("moving a window adds its destination", badges() === "1,14")

    window.fakeWorkspaces = [fake(1, 1), fake(-98, 1)]
    check("special workspace gets no badge", badges() === "1")

    window.fakeFocus = null
    window.fakeWorkspaces = [fake(11, 1)]
    check("no known focus shows occupied only", badges() === "11")

    if (failures === 0) console.log("ok: workspaces smoke")
    else console.log("workspaces smoke: " + failures + " failed")
    exitTimer.start()
  }

  // Quitting from onCompleted has no receivers yet; defer past start-up.
  Timer { id: exitTimer; interval: 50; onTriggered: Qt.quit() }
}
