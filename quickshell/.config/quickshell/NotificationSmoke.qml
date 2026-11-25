import Quickshell
import QtQuick
import "notifications" as Notifications

// Headless parse/instantiation harness used by the validation instructions in
// README.md. It deliberately omits layer-shell window construction.
Scope {
  id: smoke
  readonly property var service: Notifications.NotificationService
  property Component cardType: Component { Notifications.NotificationCard {} }
  property Component stackType: Component {
    Notifications.NotificationStack { ownerScreen: "smoke" }
  }
  Timer {
    interval: 250
    running: true
    onTriggered: {
      const card = cardType.createObject(null, {
        summary: "Screenshot ready", body: "Copied to clipboard",
        actionsJson: JSON.stringify([
          {identifier: "edit", text: "Edit"}, {identifier: "save", text: "Save"}
        ])
      })
      if (!card) { console.log("FAIL: screenshot action card could not be created"); Qt.quit(); return }
      const edit = smoke.find(card, "notificationAction-edit")
      const save = smoke.find(card, "notificationAction-save")
      if (!edit || !save || !edit.visible || !save.visible || edit.mapToItem(card, 0, 0).y <= 0)
        console.log("FAIL: Edit and Save buttons are missing below the notification")
      else {
        if (save.mapToItem(card, 0, save.height).y >= card.height)
          console.log("FAIL: notification clips its action buttons")
        let chosen = ""
        card.actionRequested.connect(function(identifier) { chosen = identifier })
        edit.clicked()
        if (chosen !== "edit") console.log("FAIL: Edit button did not request edit")
        save.clicked()
        if (chosen !== "save") console.log("FAIL: Save button did not request save")
        let invoked = ""
        const key = "1234-7"
        service.insertEntry({key: key, summary: "Fixture"}, true)
        service.liveRefs[key] = {actions: [
          {identifier: "save", invoke: function() { invoked = "save" }}
        ]}
        if (service.invokeKey(key, "save") !== "invoked" || invoked !== "save")
          console.log("FAIL: notification service did not invoke the selected action")
        else console.log("ok: notification action rendering and invocation")
        const restored = service.normalizedEntry({restored: true, actionsJson: card.actionsJson})
        if (restored.actionsJson !== "[]") console.log("FAIL: restored notification exposes expired actions")
      }
      card.destroy()
      smoke.checkBodies()
    }
  }

  property Component windowType: Component { Window { visible: true; width: 600; height: 700; color: "#1a1b26" } }
  property var bodyChecks: ({})

  function checkBodies() {
    const lines = []
    for (let i = 1; i <= 6; i++) lines.push("step " + i + " sort < in > out && echo \"&amp;\"")
    const command = lines.join("\n")
    const win = windowType.createObject(null)
    const verbatim = cardType.createObject(win.contentItem, {summary: "Allow command?", body: command, verbatim: true,
      actionsJson: JSON.stringify([{identifier: "allow", text: "Allow once"}, {identifier: "deny", text: "Deny"}])})
    const plain = cardType.createObject(win.contentItem, {summary: "Long", body: lines.join(" "), y: 400})
    const tall = cardType.createObject(win.contentItem, {summary: "Tall", verbatim: true, x: 400,
      body: Array.from({length: 40}, function(_, i) { return "line " + i }).join("\n")})
    smoke.bodyChecks = {win: win, verbatim: verbatim, plain: plain, tall: tall, command: command}
    bodyTimer.start()
  }

  Timer {
    id: bodyTimer
    interval: 200
    onTriggered: {
      const c = smoke.bodyChecks
      const text = smoke.find(c.verbatim, "notificationBodyVerbatim")
      if (!text || text.text !== c.command) console.log("FAIL verbatim body text equals input")
      else console.log("ok   verbatim body text equals input")
      if (!text || text.truncated || text.lineCount < 6) console.log("FAIL verbatim body not elided, lineCount >= 6")
      else console.log("ok   verbatim body not elided, lineCount >= 6")
      const allow = smoke.find(c.verbatim, "notificationAction-allow")
      if (!allow || allow.mapToItem(c.verbatim, 0, allow.height).y >= c.verbatim.height)
        console.log("FAIL verbatim card keeps its buttons inside")
      else console.log("ok   verbatim card keeps its buttons inside")
      const plainText = smoke.find(c.plain, "notificationBody")
      if (!plainText || plainText.lineCount !== 3 || !plainText.truncated)
        console.log("FAIL non-verbatim long body stays capped at 3 lines")
      else console.log("ok   non-verbatim long body stays capped at 3 lines")
      const view = smoke.find(c.tall, "notificationBodyVerbatimView")
      if (!view || !view.interactive || view.height >= view.contentHeight)
        console.log("FAIL verbatim body taller than 14 lines scrolls")
      else console.log("ok   verbatim body taller than 14 lines scrolls")
      const shotDir = Quickshell.env("NOTIFICATION_SMOKE_SHOT_DIR")
      if (!shotDir) { Qt.quit(); return }
      c.verbatim.grabToImage(function(image) {
        console.log((image.saveToFile(shotDir + "/verbatim-card.png") ? "ok   " : "FAIL ") + "verbatim card png")
        Qt.quit()
      })
    }
  }

  function find(item, name) {
    if (item.objectName === name) return item
    for (let i = 0; i < item.children.length; i++) {
      const match = find(item.children[i], name)
      if (match) return match
    }
    return null
  }
}
