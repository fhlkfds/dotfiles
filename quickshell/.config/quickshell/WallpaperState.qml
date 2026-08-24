pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Wallpaper data and actions for the shared cover-flow picker.
Singleton {
  id: root

  property bool panelVisible: false
  property string panelScreen: ""
  property string mode: "local" // local | query | results
  property string query: ""
  property string wallhavenQuery: ""
  property int page: 1
  property int lastPage: 1
  property int selectedIndex: 0
  property string activeSlug: ""
  property string lastError: ""
  property bool loading: false
  property bool applying: false
  property var localItems: []
  property var resultItems: []

  readonly property string backend:
    Quickshell.env("HOME") + "/.local/bin/hypr-wallpaper-picker"

  function entry(kind, slug, name, wallpaper, extra) {
    const item = {
      kind: kind,
      slug: slug,
      name: name,
      wallpaper: wallpaper || "",
      colors: {},
      style: {},
      searchText: (name + " " + (wallpaper || "")).toLowerCase()
    }
    if (extra) {
      for (const key in extra)
        item[key] = extra[key]
    }
    return item
  }

  readonly property var searchEntry:
    root.entry("search", "__wallhaven_search",
               root.query.trim() === ""
                 ? "Search Wallhaven"
                 : "Search Wallhaven for “" + root.query.trim() + "”",
               "")
  readonly property var queryEntry:
    root.entry("query", "__wallhaven_query", "Search Wallhaven", "")

  readonly property var currentItems: {
    if (root.mode === "query")
      return [root.queryEntry]
    if (root.mode === "results")
      return root.resultItems
    return root.localItems.concat([root.searchEntry])
  }

  readonly property var filtered: {
    if (root.mode === "query" || root.query.trim() === "")
      return root.currentItems
    const q = root.query.trim().toLowerCase()
    return root.currentItems.filter(item => item.searchText.indexOf(q) !== -1)
  }

  readonly property var selected: {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.filtered.length)
      return null
    return root.filtered[root.selectedIndex]
  }
  readonly property string selectedSlug: root.selected ? root.selected.slug : ""

  readonly property string statusText: {
    if (root.lastError !== "")
      return root.lastError
    if (root.loading)
      return root.mode === "local" ? "Loading wallpapers…" : "Searching Wallhaven…"
    if (root.filtered.length === 0)
      return root.query === "" ? "No wallpapers found" : "No matching wallpapers"
    return ""
  }

  function togglePanel(screenName) {
    if (root.panelVisible && root.panelScreen === screenName) {
      root.panelVisible = false
      root.cleanup()
      return
    }
    if (screenName === "")
      return
    root.panelScreen = screenName
    root.mode = "local"
    root.query = ""
    root.selectedIndex = 0
    root.lastError = ""
    root.panelVisible = true
    root.refresh()
  }

  // Within Wallhaven, Escape is Back. From local wallpapers it closes.
  function close() {
    if (root.mode !== "local") {
      root.mode = "local"
      root.query = ""
      root.selectedIndex = 0
      root.lastError = ""
      root.cleanup()
      root.refresh()
      return
    }
    root.panelVisible = false
    root.cleanup()
  }

  function cleanup() {
    if (!cleanupProc.running)
      cleanupProc.running = true
  }

  Process {
    id: cleanupProc
    command: [root.backend, "cleanup"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function refresh() {
    if (indexProc.running)
      return
    root.loading = root.mode === "local"
    indexProc.running = true
  }

  Process {
    id: indexProc
    command: [root.backend, "index"]
    stdout: StdioCollector { id: indexOut }
    stderr: StdioCollector { id: indexErr }
    onExited: function (code) {
      if (root.mode === "local")
        root.loading = false
      if (code !== 0) {
        root.lastError = indexErr.text.trim() || "Could not list wallpapers"
        return
      }
      try {
        const data = JSON.parse(indexOut.text)
        root.localItems = (data.items || []).map(item =>
          root.entry("local", item.slug, item.name, item.wallpaper,
                     { path: item.path }))
        if (root.mode === "local") {
          root.lastError = ""
          root.reselect(root.activeSlug)
        }
      } catch (e) {
        root.lastError = "Could not read the wallpaper list: " + e
      }
    }
  }

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

  function setQuery(value) {
    const wanted = root.selectedSlug
    root.query = value
    root.reselect(wanted)
  }

  function reselect(slug) {
    const items = root.filtered
    if (items.length === 0) {
      root.selectedIndex = 0
      return
    }
    if (slug !== "") {
      for (let i = 0; i < items.length; i++) {
        if (items[i].slug === slug) {
          root.selectedIndex = i
          return
        }
      }
    }
    root.selectedIndex = 0
  }

  function moveSelection(delta) {
    const count = root.filtered.length
    if (count > 0)
      root.selectedIndex = ((root.selectedIndex + delta) % count + count) % count
  }

  function selectFirst() {
    if (root.filtered.length > 0)
      root.selectedIndex = 0
  }

  function selectLast() {
    if (root.filtered.length > 0)
      root.selectedIndex = root.filtered.length - 1
  }

  function enterSearch() {
    root.mode = "query"
    root.query = ""
    root.selectedIndex = 0
    root.lastError = ""
  }

  function search(pageNumber) {
    const text = root.mode === "query" ? root.query.trim() : root.wallhavenQuery
    if (text === "") {
      root.lastError = "Type a Wallhaven query"
      return
    }
    root.wallhavenQuery = text
    root.loading = true
    root.lastError = ""
    searchProc.command = [root.backend, "search", text, String(pageNumber)]
    searchProc.running = true
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOut }
    stderr: StdioCollector { id: searchErr }
    onExited: function (code) {
      root.loading = false
      if (code !== 0) {
        root.lastError = searchErr.text.trim() || "Wallhaven search failed"
        return
      }
      try {
        const data = JSON.parse(searchOut.text)
        const items = []
        for (const item of (data.items || [])) {
          if (item.kind === "local") {
            items.push(root.entry("local", item.slug, item.name,
                                  item.wallpaper, { path: item.path }))
          } else {
            items.push(root.entry("wallhaven", item.slug, item.name,
                                  item.wallpaper,
                                  { id: item.id, url: item.url }))
          }
        }
        if (data.page > 1)
          items.push(root.entry("previous", "__previous_page",
                                "Previous page", ""))
        if (data.page < data.last_page)
          items.push(root.entry("next", "__next_page", "Next page", ""))
        items.push(root.entry("new-search", "__new_search", "New search", ""))
        root.resultItems = items
        root.page = data.page
        root.lastPage = data.last_page
        root.mode = "results"
        root.query = ""
        root.selectedIndex = 0
        root.lastError = ""
      } catch (e) {
        root.lastError = "Could not read Wallhaven results: " + e
      }
    }
  }

  function activate() {
    const item = root.selected
    if (!item || root.loading || root.applying)
      return
    switch (item.kind) {
    case "search":
      if (root.query.trim() !== "") {
        root.wallhavenQuery = root.query.trim()
        root.search(1)
        return
      }
      root.enterSearch()
      return
    case "new-search":
      root.enterSearch()
      return
    case "query":
      root.search(1)
      return
    case "previous":
      root.search(root.page - 1)
      return
    case "next":
      root.search(root.page + 1)
      return
    }

    root.pendingSlug = item.slug
    root.pendingKind = item.kind
    root.applying = true
    root.lastError = ""
    applyProc.command = item.kind === "wallhaven"
      ? [root.backend, "activate", item.id, item.url]
      : [root.backend, "apply", item.path]
    applyProc.running = true
  }

  property string pendingSlug: ""
  property string pendingKind: ""

  Process {
    id: applyProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: applyErr }
    onExited: function (code) {
      root.applying = false
      if (code !== 0) {
        root.lastError = applyErr.text.trim() || "Could not apply wallpaper"
        if (root.pendingKind === "wallhaven")
          root.refresh()
        return
      }
      root.activeSlug = root.pendingSlug
      root.panelVisible = false
      root.cleanup()
    }
  }
}
