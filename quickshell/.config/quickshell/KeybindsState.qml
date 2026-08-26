pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Keybindings palette, backed by the live `hyprctl binds` output rather than by
// parsing keybindings.lua. The running compositor is the source of truth, so the
// list can never drift from what the keys actually do.
//
// Rows are kept as structured records; the pretty "SUPER SHIFT + F" string is
// display only and is never reparsed to work out what to run.
Singleton {
  id: root

  property bool panelVisible: false
  // Screen the palette opened on, matching the other panels.
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

  // --- ordering ---------------------------------------------------------------
  // Matched in order against the row's description; the FIRST rule that matches
  // wins, so specific patterns must come before broad ones -- "files here
  // (terminal cwd)" has to be caught by the file-manager rule before the
  // terminal rule sees it. Ties inside a rank sort alphabetically, so anchored
  // patterns separate the headline entry from its variants. Edit this table to
  // re-prioritise the list; rules that match nothing cost nothing.
  readonly property var priorityRules: [
    { rank: 0, re: /^keybindings$/i },
    { rank: 1, re: /application menu|app menu|launcher|drun/i },
    { rank: 2, re: /^terminal$/i },
    { rank: 3, re: /^browser$/i },
    { rank: 4, re: /^files$|file manager|files here|nautilus/i },
    { rank: 5, re: /terminal/i },                       // drop-down terminal, etc.
    { rank: 6, re: /^disks$/i },
    { rank: 7, re: /help|cheat sheet/i },
    { rank: 8, re: /power menu|lock screen|exit hyprland/i },
    { rank: 9, re: /theme|wallpaper/i },
    { rank: 10, re: /fullscreen|maximi[sz]e/i },
    { rank: 11, re: /close window|float|focus|move window|swap window|resize/i },
    { rank: 12, re: /workspace/i },
    { rank: 13, re: /clip(board)?|copy|cut|paste/i },
    { rank: 14, re: /volume|mute|play|pause|track|stop playback|spotify|media/i },
    { rank: 15, re: /network|wi-?fi|bluetooth/i },
    { rank: 16, re: /emoji|calculator|calc/i },
    { rank: 17, re: /screenshot|record/i },
    { rank: 18, re: /notification|do not disturb|night light|zoom/i },
    { rank: 19, re: /brightness/i }
  ]

  function rankFor(description) {
    for (var i = 0; i < root.priorityRules.length; i++) {
      if (root.priorityRules[i].re.test(description))
        return root.priorityRules[i].rank
    }
    return 999
  }

  // --- collection -------------------------------------------------------------

  // [{ shortcut, description, dispatcher, arg, mouse, actionable, searchText, rank }]
  property var rows: []
  property string query: ""
  property int selectedIndex: 0
  property string lastError: ""

  readonly property var filtered: {
    const q = root.query.trim().toLowerCase()
    if (q === "")
      return root.rows
    return root.rows.filter(r => r.searchText.indexOf(q) !== -1)
  }

  readonly property var selected:
    (selectedIndex >= 0 && selectedIndex < filtered.length)
      ? filtered[selectedIndex] : null

  onQueryChanged: root.selectedIndex = 0

  function moveSelection(delta) {
    const n = root.filtered.length
    if (n === 0)
      return
    root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + delta))
  }

  function selectFirst() { root.selectedIndex = 0 }
  function selectLast() { root.selectedIndex = Math.max(0, root.filtered.length - 1) }

  function refresh() {
    bindsProc.running = true
  }

  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text === "")
          return
        try {
          root.build(JSON.parse(text))
          root.lastError = ""
        } catch (e) {
          root.lastError = "Could not parse hyprctl binds: " + e
        }
      }
    }
    stderr: StdioCollector { id: bindsErr }
    onExited: function (code) {
      if (code !== 0)
        root.lastError = bindsErr.text.trim() || "hyprctl binds failed"
    }
  }

  // --- normalisation ----------------------------------------------------------

  // Hyprland modmask bits. Emitted in a fixed order so the same combination
  // always renders identically.
  readonly property var modBits: [
    { bit: 64, name: "SUPER" },
    { bit: 1, name: "SHIFT" },
    { bit: 4, name: "CTRL" },
    { bit: 8, name: "ALT" }
  ]

  function modString(mask) {
    var parts = []
    for (var i = 0; i < root.modBits.length; i++) {
      if (mask & root.modBits[i].bit)
        parts.push(root.modBits[i].name)
    }
    return parts.join(" ")
  }

  // Keys that would otherwise render as an internal name or a bare symbol.
  readonly property var keyNames: ({
    "return": "RETURN",
    "kp_enter": "ENTER",
    "space": "SPACE",
    "escape": "ESCAPE",
    "tab": "TAB",
    "backspace": "BACKSPACE",
    "delete": "DELETE",
    "bracketleft": "[",
    "bracketright": "]",
    "comma": ",",
    "period": ".",
    "slash": "/",
    "backslash": "\\",
    "semicolon": ";",
    "apostrophe": "'",
    "grave": "`",
    "minus": "-",
    "equal": "=",
    "left": "LEFT",
    "right": "RIGHT",
    "up": "UP",
    "down": "DOWN",
    "print": "PRINT",
    "mouse_down": "SCROLL DOWN",
    "mouse_up": "SCROLL UP",
    "mouse:272": "LEFT CLICK",
    "mouse:273": "RIGHT CLICK",
    "mouse:274": "MIDDLE CLICK"
  })

  // X11 keycode = evdev code + 8, so the number row is a fixed table. Anything
  // outside it is shown as `code:N` rather than guessed at.
  readonly property var keycodeNames: ({
    10: "1", 11: "2", 12: "3", 13: "4", 14: "5",
    15: "6", 16: "7", 17: "8", 18: "9", 19: "0"
  })

  function keyLabel(bind) {
    const raw = String(bind.key || "")
    if (raw === "") {
      const code = Number(bind.keycode || 0)
      const named = root.keycodeNames[code]
      return named !== undefined ? named : ("code:" + code)
    }

    const lower = raw.toLowerCase()
    if (root.keyNames[lower] !== undefined)
      return root.keyNames[lower]

    // XF86AudioRaiseVolume -> VOLUME UP, XF86MonBrightnessDown -> BRIGHTNESS DOWN
    if (lower.indexOf("xf86") === 0) {
      var rest = raw.substring(4).replace(/^Audio/, "").replace(/^Mon/, "")
      // Raise/Lower lead the noun ("RaiseVolume") where Up/Down trail it
      // ("BrightnessUp"), so the direction has to be moved to the end.
      const dir = rest.match(/^(Raise|Lower)(.+)$/)
      if (dir !== null)
        rest = dir[2] + (dir[1] === "Raise" ? " Up" : " Down")
      return rest.replace(/([a-z])([A-Z])/g, "$1 $2").toUpperCase()
    }

    return raw.toUpperCase()
  }

  // --- descriptions -----------------------------------------------------------

  readonly property var dispatcherNames: ({
    "killactive": "Close window",
    "exit": "Exit Hyprland",
    "togglefloating": "Toggle floating",
    "togglesplit": "Toggle split direction",
    "pseudo": "Toggle pseudotile",
    "fullscreen": "Fullscreen",
    "movefocus": "Move focus",
    "movewindow": "Move window",
    "swapwindow": "Swap window",
    "resizeactive": "Resize window",
    "resizewindow": "Resize window (drag)",
    "workspace": "Workspace",
    "movetoworkspace": "Move to workspace",
    "movetoworkspacesilent": "Move to workspace (silent)",
    "togglespecialworkspace": "Special workspace",
    "cyclenext": "Next window"
  })

  readonly property var directionNames: ({
    "l": "left", "r": "right", "u": "up", "d": "down"
  })

  // Only derives a label when the dispatcher makes one unambiguous. Anything
  // else falls back to the command itself rather than inventing a meaning.
  function describe(bind) {
    const desc = String(bind.description || "").trim()
    if (desc !== "")
      return desc

    const dispatcher = String(bind.dispatcher || "")
    const arg = String(bind.arg || "").trim()

    if (dispatcher === "exec") {
      if (arg === "")
        return "Run command"
      const first = arg.split(/\s+/)[0]
      // A bare command name reads as an app; a path reads as a script.
      if (first.indexOf("/") === -1 && !/[;&|$]/.test(arg))
        return "Launch " + first
      const base = first.substring(first.lastIndexOf("/") + 1)
      return "Run " + (base !== "" ? base : arg)
    }

    // `bindm` reports dispatcher "mouse" with the real action in the argument,
    // and takes no description syntax, so its label always comes from here.
    if (dispatcher === "mouse") {
      const mouseName = root.dispatcherNames[arg]
      return mouseName !== undefined ? mouseName : (arg !== "" ? arg : "Mouse binding")
    }

    const name = root.dispatcherNames[dispatcher]
    if (name === undefined)
      return dispatcher === "" ? "" : dispatcher

    if (arg === "")
      return name
    if (root.directionNames[arg] !== undefined)
      return name + " " + root.directionNames[arg]
    return name + " " + arg
  }

  // --- build ------------------------------------------------------------------

  // Dispatchers that must not fire from the palette: they would act the moment
  // the menu closes, and getting them wrong ends a session or a window.
  readonly property var noExecute: ["exit", "killactive"]

  // Longest merged "A / B" shortcut worth showing on one row; past this the two
  // bindings are listed separately. Sized against Theme.menuColumnMax.
  readonly property int mergeMaxLength: 32

  function build(binds) {
    if (!Array.isArray(binds)) {
      root.rows = []
      return
    }

    const seenKeys = ({})   // shortcut slot -> already taken
    const byAction = ({})   // dispatcher|arg -> index into list
    const list = []

    for (var i = 0; i < binds.length; i++) {
      const b = binds[i]
      const dispatcher = String(b.dispatcher || "")
      if (dispatcher === "")
        continue

      const isMouse = b.mouse === true
      const key = String(b.key || "")
      const slot = String(b.modmask || 0) + "|"
                 + (key !== "" ? key : "code:" + String(b.keycode || 0))

      // Hyprland honours the first bind registered for a slot, so later ones are
      // shadowed and would only show as phantom duplicates. This is what folds
      // away the doubled wpctl/pactl volume binds.
      if (seenKeys[slot])
        continue
      seenKeys[slot] = true

      const description = root.describe(b)
      if (description === "")
        continue

      const mods = root.modString(Number(b.modmask || 0))
      const keyName = root.keyLabel(b)
      const shortcut = mods === "" ? keyName : (mods + " + " + keyName)
      const arg = String(b.arg || "").trim()

      // Two shortcuts running exactly the same thing are one row with both
      // shortcuts. Matching descriptions alone never merge -- only identical
      // dispatcher and argument.
      // Lua bind arguments are ephemeral registry IDs, so identical described
      // actions no longer share an `arg`. Description is the stable identity
      // for the duplicate bindings deliberately declared in keybindings.lua.
      const actionKey = dispatcher === "__lua"
        ? dispatcher + "|" + description
        : dispatcher + "|" + arg
      const existing = byAction[actionKey]
      if (existing !== undefined && !isMouse && !list[existing].mouse) {
        // When both use the same modifiers only the differing key is appended,
        // keeping the merged form short.
        const merged = list[existing].shortcut + " / "
          + (list[existing].mods === mods ? keyName : shortcut)
        // The shortcut column is sized from the longest entry, so a merge that
        // would not fit stays two rows rather than widening every other row.
        if (merged.length <= root.mergeMaxLength) {
          list[existing].shortcut = merged
          continue
        }
      }

      const row = {
        shortcut: shortcut,
        mods: mods,
        description: description,
        dispatcher: dispatcher,
        arg: arg,
        mouse: isMouse,
        // Mouse binds cannot be re-dispatched, and the denylist is deliberate.
        actionable: !isMouse && root.noExecute.indexOf(dispatcher) === -1,
        rank: root.rankFor(description),
        searchText: ""
      }
      byAction[actionKey] = list.length
      list.push(row)
    }

    // searchText is built last so it includes the merged alternate shortcuts.
    for (var j = 0; j < list.length; j++) {
      const r = list[j]
      r.searchText = (r.shortcut + " " + r.description + " "
                    + r.dispatcher + " " + r.arg).toLowerCase()
    }

    list.sort(function (a, b) {
      if (a.rank !== b.rank)
        return a.rank - b.rank
      return a.description.localeCompare(b.description)
    })

    root.rows = list
    if (root.selectedIndex >= root.filtered.length)
      root.selectedIndex = 0
  }

  // --- activation -------------------------------------------------------------

  // Closes first, then dispatches on the next tick, so window-relative
  // dispatchers act on the toplevel underneath instead of the dismissing overlay.
  function activate(row) {
    root.panelVisible = false
    if (!row || !row.actionable)
      return
    pending.row = row
    pending.restart()
  }

  Timer {
    id: pending
    property var row: null
    interval: 20
    repeat: false
    onTriggered: {
      const r = pending.row
      pending.row = null
      if (!r)
        return
      // Lua binds are exposed as __lua plus a registry reference. Hyprland
      // does not yet expose a public invoke-by-reference API, so validate the
      // numeric reference and contain the current registry lookup here.
      if (r.dispatcher === "__lua" && /^\d+$/.test(r.arg)) {
        const code = "local action = debug.getregistry()[" + r.arg + "]; "
                   + "assert(type(action) == 'function', 'invalid bind action'); action()"
        actionProc.command = ["hyprctl", "eval", code]
      } else {
        actionProc.command = r.arg === ""
          ? ["hyprctl", "dispatch", r.dispatcher]
          : ["hyprctl", "dispatch", r.dispatcher, r.arg]
      }
      actionProc.running = true
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: actionErr }
    onExited: function (code) {
      if (code !== 0)
        console.warn("Keybinds: dispatch failed:", actionErr.text.trim())
    }
  }

  readonly property string glyphSearch: String.fromCodePoint(0xf0349) // md-magnify
}
