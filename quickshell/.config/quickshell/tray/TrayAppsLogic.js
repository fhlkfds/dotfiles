// Which app icons the bar draws, and which Hyprland window each one belongs
// to. Pure: the tray and launcher pass in tray items, pinned apps and windows,
// so the rules run under node and in the headless smokes.
//
// Names are matched loosely because every app spells itself differently:
// Spotify's tray item says "spotify-client", its window "Spotify", the pinned
// config "spotify"; Hermes' tray item id is "tray-icon tray app hermes-chat".

// Lower case, letters and digits only: "Spotify" and "spotify-client" become
// "spotify" and "spotifyclient".
function norm(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
}

// "image://icon/spotify-linux-32" → "spotify-linux-32"; a file path keeps its
// base name without the extension.
function iconName(icon) {
  let name = String(icon || "").replace(/^image:\/\/icon\//, "").replace(/\?.*$/, "")
  name = name.slice(name.lastIndexOf("/") + 1)
  return name.replace(/\.(png|svg|xpm)$/i, "")
}

// Plain arrays, Quickshell ObjectModels ({ values }), and QML lists. A QML
// list (ObjectModel.values) indexes like an array but is not a JS Array.
function arrayLike(value) {
  return !!value && typeof value === "object" && typeof value.length === "number"
}

function list(values) {
  if (!values) return []
  if (Array.isArray(values)) return values
  if (arrayLike(values)) return Array.prototype.slice.call(values)
  if (arrayLike(values.values)) return Array.prototype.slice.call(values.values)
  return []
}

// The names a tray item goes by, most specific first.
function trayNames(item) {
  return [item && item.title, item && item.id, item && iconName(item.icon)].map(norm).filter(n => n.length > 0)
}

function appNames(app) {
  return [app && app.wmClass, app && app.desktopId, app && app.icon].map(norm).filter(n => n.length > 0)
}

// 2: some name equals the class. 1: a name contains it (only for classes of
// four or more characters, so "kit" cannot match "kittyfoo"). 0: no match.
function score(names, appId) {
  const target = norm(appId)
  if (target.length === 0) return 0
  if (names.indexOf(target) >= 0) return 2
  if (target.length < 4) return 0
  return names.some(n => n.indexOf(target) >= 0) ? 1 : 0
}

function best(names, windows) {
  let found = null
  let top = 0
  for (const w of list(windows)) {
    const s = score(names, w && w.appId)
    if (s > top) { top = s; found = w }
  }
  return found
}

function windowFor(item, windows) {
  return best(trayNames(item), windows)
}

// A pinned app names its window class in app-launcher.json; that is the only
// name used, compared without case ("spotify" finds "Spotify").
function windowForApp(app, windows) {
  const cls = norm(app && app.wmClass)
  return cls.length > 0 ? best([cls], windows) : null
}

// The tray item a pinned app stands in for, so its icon can open that menu.
function trayItemForApp(app, items) {
  const names = appNames(app)
  for (const item of list(items))
    for (const n of trayNames(item))
      if (score(names, n) > 0 || score([n], app && app.wmClass) > 0) return item
  return null
}

// One icon per app: drop tray items whose app is pinned (the pinned icon
// opens the menu instead) and later items for an app already shown.
function visibleItems(items, pinnedApps) {
  const pinned = list(pinnedApps)
  const seen = {}
  const shown = []
  for (const item of list(items)) {
    if (pinned.some(app => trayItemForApp(app, [item]) !== null)) continue
    const key = trayNames(item)[0] || ""
    if (key.length > 0 && seen[key]) continue
    seen[key] = true
    shown.push(item)
  }
  return shown
}

// Hyprland focuses a window by address and switches to its workspace. It
// reports addresses without 0x; anything but hex is refused so a stray value
// cannot inject into the Lua dispatch.
function focusRequest(address) {
  const hex = String(address || "").replace(/^0x/i, "")
  if (!/^[0-9a-fA-F]+$/.test(hex)) return ""
  return 'hl.dsp.focus({ window = "address:0x' + hex + '" })'
}

// Hyprland toplevels → { address, appId }: the Wayland app id, else the class
// from the last IPC refresh.
function windowsFrom(toplevels) {
  return list(toplevels).map(t => ({
    address: String((t && t.address) || ""),
    appId: String((t && t.wayland && t.wayland.appId)
      || (t && t.lastIpcObject && t.lastIpcObject.class) || ""),
  }))
}

if (typeof module !== "undefined" && module) {
  module.exports = {
    windowFor: windowFor,
    windowForApp: windowForApp,
    trayItemForApp: trayItemForApp,
    visibleItems: visibleItems,
    focusRequest: focusRequest,
    windowsFrom: windowsFrom,
  }
}
