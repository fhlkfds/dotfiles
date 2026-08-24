pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// State for the web app manager overlay (Super+Shift+A).
//
// This is a front-end only. Every filesystem and network operation lives in the
// `webapp` backend; the shell just collects a name and a URL, shows what the
// backend reports, and asks it to install or remove. Nothing here builds a shell
// command string -- each Process takes an argument array, so a name or URL can
// never be reinterpreted as syntax.
//
//   webapp list --json          -> apps[]        (the model)
//   webapp discover-icon <url>  -> icon preview   (async, never blocks the UI)
//   webapp install ...          -> creates metadata + icon + .desktop
//   webapp remove <id>          -> removes exactly those three
Singleton {
  id: root

  // --- panel lifecycle --------------------------------------------------------

  property bool panelVisible: false
  property string panelScreen: ""

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
    root.refresh()
  }

  function close() {
    root.panelVisible = false
  }

  // --- backend ----------------------------------------------------------------
  // Invoked by path rather than relying on `webapp` being on PATH: the shell is
  // started by Hyprland, whose environment does not include ~/.local/bin.

  readonly property string manager:
    Quickshell.env("HOME") + "/.config/hypr/webapp/manager.py"

  // --- model ------------------------------------------------------------------

  property var apps: []
  property var loadErrors: []
  property string lastError: ""
  property bool loading: false

  function refresh() {
    root.loading = true
    listProc.running = true
  }

  Process {
    id: listProc
    command: ["python3", root.manager, "list", "--json"]

    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        try {
          const data = JSON.parse(text)
          root.apps = data["apps"] || []
          root.loadErrors = data["errors"] || []
          root.lastError = ""
        } catch (e) {
          root.lastError = "Could not read the web app list: " + e
        }
      }
    }
    stderr: StdioCollector { id: listErr }

    onExited: function (code) {
      root.loading = false
      if (code !== 0 && root.apps.length === 0)
        root.lastError = listErr.text.trim() || "webapp list failed"
    }
  }

  // --- install form -----------------------------------------------------------
  // Kept on the singleton so a half-filled form survives closing the overlay.

  property string formName: ""
  property string formUrl: ""
  property string iconPath: ""      // staged icon the backend found or the user picked
  property string iconState: ""     // "", "searching", "found", "none", "chosen"
  property bool installing: false
  property string formError: ""

  function resetForm() {
    root.formName = ""
    root.formUrl = ""
    root.iconPath = ""
    root.iconState = ""
    root.formError = ""
  }

  // Mirrors the backend's rules closely enough to gate the Install button
  // without a round-trip on every keystroke. The backend re-validates
  // authoritatively -- this only decides whether the button is live.
  readonly property bool nameValid: root.formName.trim().length > 0
                                 && root.formName.trim().length <= 96
  readonly property bool urlValid: {
    const u = root.formUrl.trim()
    if (u.length === 0)
      return false
    if (/\s/.test(u))
      return false
    // A scheme other than http(s) is invalid; no scheme at all is fine and gets
    // promoted to https by the backend.
    const m = /^([a-zA-Z][a-zA-Z0-9+.\-]*):/.exec(u)
    if (m && m[1].toLowerCase() !== "http" && m[1].toLowerCase() !== "https") {
      // "localhost:8080/app" is a host:port, not a scheme.
      const rest = u.slice(m[0].length)
      if (!/^\d+(\/|$)/.test(rest))
        return false
    }
    const host = u.replace(/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//, "").split(/[\/?#]/)[0]
    return host.indexOf(".") !== -1 || host.split(":")[0] === "localhost"
  }
  readonly property bool canInstall: root.nameValid && root.urlValid
                                  && !root.installing

  // Icon discovery is debounced so typing a URL does not fire a request per
  // keystroke, and runs in its own process so the shell never waits on the
  // network.
  Timer {
    id: iconDebounce
    interval: 700
    onTriggered: root.discoverIcon()
  }

  function urlEdited(text) {
    root.formUrl = text
    root.formError = ""
    if (root.iconState !== "chosen") {
      root.iconPath = ""
      root.iconState = ""
      if (root.urlValid)
        iconDebounce.restart()
      else
        iconDebounce.stop()
    }
  }

  function discoverIcon() {
    if (!root.urlValid)
      return
    root.iconState = "searching"
    iconProc.command = ["python3", root.manager, "discover-icon", root.formUrl.trim()]
    iconProc.running = true
  }

  Process {
    id: iconProc
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        try {
          const d = JSON.parse(text)
          if (d.ok) {
            root.iconPath = d.path
            root.iconState = "found"
            // Only ever fills an empty field; never overwrites what was typed.
            if (root.formName.trim() === "" && d.suggested_name)
              root.formName = d.suggested_name
          } else {
            root.iconPath = ""
            root.iconState = "none"
          }
        } catch (e) {
          root.iconState = "none"
        }
      }
    }
    stderr: StdioCollector {}
    onExited: function (code) {
      if (code !== 0 && root.iconState === "searching")
        root.iconState = "none"
    }
  }

  function chooseIcon(path) {
    if (!path)
      return
    root.iconPath = path
    root.iconState = "chosen"
  }

  // --- install ----------------------------------------------------------------

  function install() {
    if (!root.canInstall)
      return
    root.installing = true
    root.formError = ""
    // An argument array: the name and URL are separate argv entries, so quoting
    // and metacharacters are a non-issue.
    const cmd = ["python3", root.manager, "install",
                 "--name", root.formName.trim(),
                 "--url", root.formUrl.trim(), "--json"]
    if (root.iconPath !== "")
      cmd.push("--icon", root.iconPath)
    installProc.command = cmd
    installProc.running = true
  }

  signal installed(string name)

  Process {
    id: installProc
    stdout: StdioCollector { id: installOut }
    stderr: StdioCollector { id: installErr }
    onExited: function (code) {
      root.installing = false
      if (code !== 0) {
        // Surfaced in the form, not swallowed: the backend's message is the
        // actionable part (duplicate id, bad URL, unwritable directory).
        root.formError = installErr.text.trim() || "install failed"
        console.warn("WebAppState: install failed:", root.formError)
        return
      }
      const name = root.formName.trim()
      root.resetForm()
      root.refresh()
      root.installed(name)
    }
  }

  // --- remove -----------------------------------------------------------------
  // Two-step: the row asks first. The shell has no confirmation dialog anywhere,
  // so this is an in-row confirm rather than a modal.

  property string confirmingId: ""

  function askRemove(id) { root.confirmingId = id }
  function cancelRemove() { root.confirmingId = "" }

  function remove(id) {
    if (!id)
      return
    root.confirmingId = ""
    removeProc.command = ["python3", root.manager, "remove", id, "--json"]
    removeProc.running = true
  }

  Process {
    id: removeProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: removeErr }
    onExited: function (code) {
      if (code !== 0)
        root.lastError = removeErr.text.trim() || "remove failed"
      else
        root.lastError = ""
      root.refresh()
    }
  }

  // Choosing an icon by hand.
  //
  // There is deliberately no native file dialog: Quickshell provides none, and
  // this desktop has no zenity/kdialog/yad to borrow one from. Rather than pull
  // in a dependency for a rarely-used path, an icon can be supplied two ways
  // that need nothing extra -- drag an image file onto the preview, or type a
  // path. The backend sniffs the file's magic bytes either way, so a wrong file
  // is rejected with a clear message rather than producing a broken launcher.
  property bool iconPathFieldVisible: false

  function setIconPath(path) {
    let p = (path || "").trim()
    if (p === "")
      return
    // A drop arrives as a file:// URL; the backend wants a plain path.
    if (p.indexOf("file://") === 0)
      p = decodeURIComponent(p.substring(7))
    root.chooseIcon(p)
  }

  function clearChosenIcon() {
    root.iconPath = ""
    root.iconState = ""
    if (root.urlValid)
      root.discoverIcon()
  }

  // Nerd Font glyphs; codepoints above U+FFFF need fromCodePoint, not \u.
  readonly property string glyphWeb: String.fromCodePoint(0xf0ac7)
  readonly property string glyphAdd: String.fromCodePoint(0xf0415)
  readonly property string glyphDelete: String.fromCodePoint(0xf01b4)
  readonly property string glyphBack: String.fromCodePoint(0xf004d)
}
