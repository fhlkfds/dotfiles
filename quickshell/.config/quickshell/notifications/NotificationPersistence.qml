import Quickshell
import Quickshell.Io
import QtQuick
import "NotificationLogic.js" as Logic

QtObject {
  id: root

  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/notificationctl"
  property var queue: []
  property var activeJob: null

  signal operationFailed(string operation, string detail)

  function enqueue(args, callback, input) {
    root.queue = root.queue.concat([{
      args: args,
      callback: callback || null,
      input: String(input || "")
    }])
    root.runNext()
  }

  function runNext() {
    if (worker.running || root.activeJob || root.queue.length === 0)
      return
    root.activeJob = root.queue[0]
    root.queue = root.queue.slice(1)
    worker.command = [root.helper].concat(root.activeJob.args)
    worker.pendingInput = root.activeJob.input
    worker.running = true
  }

  function initialize(callback) {
    enqueue(["_init"], callback)
  }

  function writeActive(entry) {
    const clean = Logic.persistableEntry(entry)
    enqueue(["_write-active", clean.key,
             "--limit", String(NotificationConfig.historyLimit)], null,
            JSON.stringify(clean))
  }

  function writeHistory(entry) {
    const clean = Logic.persistableEntry(entry)
    enqueue(["_write-history", clean.key,
             "--limit", String(NotificationConfig.historyLimit)], null,
            JSON.stringify(clean))
  }

  function archive(entry) {
    enqueue(["_archive", entry.key, "--limit", String(NotificationConfig.historyLimit)])
  }

  function removeActive(entry) {
    enqueue(["_remove-active", entry.key])
  }

  function readActive(callback) {
    enqueue(["_read-active"], callback)
  }

  function readHistory(callback) {
    enqueue(["_read-history"], callback)
  }

  function clearHistory(callback) {
    enqueue(["_clear-history"], callback)
  }

  function sweep() {
    enqueue(["_sweep"])
  }

  property Process worker: Process {
    id: worker
    property string pendingInput: ""
    running: false
    stdinEnabled: true
    stdout: StdioCollector { id: output; waitForEnd: true }
    stderr: StdioCollector { id: errors; waitForEnd: true }
    onStarted: {
      if (pendingInput.length > 0) worker.write(pendingInput + "\n")
    }
    onExited: function(code) {
      const job = root.activeJob
      root.activeJob = null
      if (code !== 0)
        root.operationFailed(job && job.args.length ? job.args[0] : "unknown", errors.text.trim())
      if (job && job.callback) {
        try { job.callback(output.text, code) }
        catch (e) { console.warn("notifications: persistence callback failed:", e) }
      }
      root.runNext()
    }
  }
}
