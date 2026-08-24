pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// State for the fullscreen theme picker (Super+Ctrl+Shift+Space).
//
// The picker is a front-end only: this singleton never touches Waybar, Kitty,
// Rofi, Zsh, Hyprland or the wallpaper itself. It reads a model from the theme
// backend and hands a slug back to that same backend, which owns every side
// effect and remains the single source of truth for what theme is active.
//
//   theme index --json  ->  themes[]            (model, one spawn per open)
//   theme set <slug>    ->  the whole desktop   (only from activate())
//
// Panel lifecycle matches every other panel in the shell: panelVisible +
// panelScreen + togglePanel() + close(), so only the instance on the focused
// monitor ever shows.
Singleton {
  id: root

  // --- panel lifecycle --------------------------------------------------------

  property bool panelVisible: false
  // Screen the picker opened on, matching the other panels.
  property string panelScreen: ""

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    // An IPC call with no focused monitor is a no-op rather than opening the
    // overlay on every screen at once.
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
  // The generator is invoked directly rather than through the `theme` wrapper on
  // PATH: the shell is started by Hyprland, whose environment does not include
  // ~/.local/bin. Same code either way -- the wrapper only execs this.

  readonly property string generator:
    Quickshell.env("HOME") + "/.config/hypr/theme/generate.py"

  // --- model ------------------------------------------------------------------

  property var themes: []          // rows from `theme index --json`
  property string activeSlug: ""   // theme currently applied to the desktop
  property var loadErrors: []      // themes whose colors.toml could not be read
  property string lastError: ""
  property bool loading: false

  function refresh() {
    root.loading = true
    indexProc.running = true
  }

  Process {
    id: indexProc
    command: ["python3", root.generator, "index", "--json"]

    stdout: StdioCollector {
      onTextChanged: {
        if (text === "")
          return
        try {
          const data = JSON.parse(text)
          // Read before the model is replaced: `selected` indexes the old list.
          const wasFocused = root.selectedSlug
          root.themes = (data["themes"] || []).map(function (t) {
            // Precompute the haystack once per load rather than per keystroke.
            t.searchText = (String(t.name || "") + " " + String(t.slug || "")
                            + " " + String(t.family || "")).toLowerCase()
            return t
          })
          root.activeSlug = data["active"] || ""
          root.loadErrors = data["errors"] || []
          root.lastError = ""
          // On the first load of an open picker nothing is focused yet (the
          // index arrives asynchronously, after onVisibleChanged has run), so
          // fall back to the theme that is actually applied. That way the
          // gallery opens showing you where you are rather than at the top.
          root.reselect(wasFocused !== "" ? wasFocused : root.activeSlug)
        } catch (e) {
          root.lastError = "Could not parse theme index: " + e
        }
      }
    }
    stderr: StdioCollector { id: indexErr }

    onExited: function (code) {
      root.loading = false
      if (code !== 0 && root.themes.length === 0)
        root.lastError = indexErr.text.trim() || "theme index failed"
    }
  }

  // --- filtering --------------------------------------------------------------

  property string query: ""
  property int selectedIndex: 0

  readonly property var filtered: {
    const q = root.query.trim().toLowerCase()
    if (q === "")
      return root.themes
    return root.themes.filter(t => t.searchText.indexOf(q) !== -1)
  }

  readonly property var selected: {
    const f = root.filtered
    if (root.selectedIndex < 0 || root.selectedIndex >= f.length)
      return null
    return f[root.selectedIndex]
  }

  readonly property string selectedSlug: root.selected ? root.selected.slug : ""

  // Filtering goes through here rather than a plain `query` write plus an
  // onQueryChanged handler. The handler would be racing the `filtered` binding:
  // by the time it ran, the selection may already have been recomputed against
  // the new filter, so the slug it was meant to preserve would be gone. Reading
  // it first, explicitly, removes the ordering question entirely.
  // The carousel has no search box; keys are handled by the overlay and the
  // query is assembled here.
  function appendToQuery(ch) {
    root.setQuery(root.query + ch)
  }

  function backspaceQuery() {
    if (root.query.length > 0)
      root.setQuery(root.query.slice(0, -1))
  }

  function clearQuery() {
    root.setQuery("")
  }

  function setQuery(q) {
    const wanted = root.selectedSlug
    root.query = q
    root.reselect(wanted)
  }

  // Point selectedIndex back at `slug` if it survived, else fall back to the
  // first result. This is what keeps the index valid when the focused item is
  // filtered away, and what stops a stale index pointing past the end.
  function reselect(slug) {
    const f = root.filtered
    if (f.length === 0) {
      root.selectedIndex = 0
      return
    }
    if (slug !== "") {
      for (let i = 0; i < f.length; i++) {
        if (f[i].slug === slug) {
          root.selectedIndex = i
          return
        }
      }
      // Only worth reporting when the *active* theme has vanished from disk --
      // a filter simply hiding the selection is normal and not a problem.
      if (slug === root.activeSlug && root.query === "")
        console.warn("ThemeState: active theme '" + slug
                     + "' is not in the theme index; falling back to the first entry")
    }
    root.selectedIndex = 0
  }

  // The one message covering every reason the gallery may not be showing what
  // you expect. Derived from state rather than assembled in the view, so the
  // panel just displays it.
  readonly property string statusText: {
    if (root.lastError !== "")
      return root.lastError
    if (root.loading && root.themes.length === 0)
      return "Loading themes…"
    if (root.themes.length === 0)
      return "No themes found in ~/.config/hypr/themes"
    if (root.filtered.length === 0)
      return "No matching themes"
    // A malformed theme is surfaced without hiding the ones that did load.
    if (root.loadErrors.length > 0)
      return root.loadErrors.length
           + " theme(s) could not be read and are not listed"
    return ""
  }

  // Wrapping, unlike the keybindings palette: a carousel has no ends, so running
  // off the right edge comes back round to the first theme.
  function moveSelection(delta) {
    const n = root.filtered.length
    if (n === 0)
      return
    root.selectedIndex = ((root.selectedIndex + delta) % n + n) % n
  }

  // Clicking a side slice selects it and nothing more.
  function selectSlug(slug) {
    root.reselect(slug)
  }

  function selectFirst() {
    if (root.filtered.length > 0)
      root.selectedIndex = 0
  }

  function selectLast() {
    if (root.filtered.length > 0)
      root.selectedIndex = root.filtered.length - 1
  }

  // --- activation -------------------------------------------------------------
  // The ONLY path that applies a theme. Moving the selection never comes here,
  // so arrowing through the gallery costs nothing.

  property bool applying: false

  function activate() {
    const item = root.selected
    if (!item || root.applying)
      return
    root.pendingSlug = item.slug
    root.pendingName = item.name
    root.lastError = ""
    // The overlay stays up until the backend reports success. Closing first
    // would hide a failure, and the picker is where a retry has to happen.
    root.applying = true
    applyDelay.restart()
  }

  property string pendingSlug: ""
  property string pendingName: ""

  Timer {
    id: applyDelay
    interval: 20
    onTriggered: applyProc.running = true
  }

  Process {
    id: applyProc
    // An argument array, not a shell string: a slug is passed as exactly one
    // argv entry, so spaces or shell metacharacters in a theme name cannot be
    // reinterpreted as syntax.
    command: ["python3", root.generator, "set", root.pendingSlug]

    stdout: StdioCollector { id: applyOut }
    stderr: StdioCollector { id: applyErr }

    onExited: function (code) {
      root.applying = false
      if (code !== 0) {
        // Never silently claim success, and never close on failure: the picker
        // stays open showing the error so the selection can be retried.
        root.lastError = applyErr.text.trim()
          || ("Could not apply " + root.pendingName + " (exit " + code + ")")
        console.warn("ThemeState: theme set failed:", root.lastError)
        return
      }
      root.lastError = ""
      // current-theme has moved; keep the active marker in step without
      // re-reading the whole index.
      root.activeSlug = root.pendingSlug
      root.panelVisible = false
    }
  }

  // Nerd Font glyphs. Codepoints must go through String.fromCodePoint rather
  // than a \u escape, which cannot express the private-use plane.
  readonly property string glyphSearch: String.fromCodePoint(0xf0349)
  readonly property string glyphActive: String.fromCodePoint(0xf0765)
  readonly property string glyphPalette: String.fromCodePoint(0xf0e2b)
}
