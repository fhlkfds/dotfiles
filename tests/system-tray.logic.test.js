"use strict";

// Pure rules behind the bar's app icons: which tray items to draw, and which
// Hyprland window a tray item or pinned app belongs to. Run by
// tests/system-tray.test.sh as `node <this> <TrayAppsLogic.js>`.
const logic = require(process.argv[2]);

let failures = 0;
function check(label, ok) {
  if (ok) console.log("ok   " + label);
  else { failures++; console.log("FAIL " + label); }
}

// Shapes taken from the live session that reported the bug: the tray items'
// D-Bus Id/Title/IconName and Hyprland's app ids and (0x-less) addresses.
const spotifyTray = { id: "spotify-client", title: "spotify", icon: "image://icon/spotify-linux-32" };
const hermesTray = {
  id: "tray-icon tray app hermes-chat",
  title: "hermes-chat",
  icon: "image://icon//run/user/1000/tray-icon/tray-icon-hermes-chat-0.png",
};
const nmTray = { id: "nm-applet", title: "NetworkManager Applet", icon: "image://icon/nm-signal-75" };
const windows = [
  { address: "56462b273980", appId: "Spotify" },
  { address: "56462b2a28c0", appId: "virt-manager" },
  { address: "56462b3205c0", appId: "hermes-chat" },
  { address: "56462b14ec10", appId: "kitty" },
];
const spotifyPin = { desktopId: "spotify", name: "Spotify", icon: "spotify-client", wmClass: "spotify" };

// Each tray item finds its own window, whatever the case or punctuation.
check("Spotify tray item finds the Spotify window (class differs in case)",
  logic.windowFor(spotifyTray, windows)?.address === "56462b273980");
check("Hermes tray item finds the hermes-chat window",
  logic.windowFor(hermesTray, windows)?.address === "56462b3205c0");
check("a tray item with no window finds nothing",
  logic.windowFor(nmTray, windows) === null);
check("no windows yet (startup) finds nothing", logic.windowFor(spotifyTray, []) === null);

// An exact name beats a looser one: "spotify" must not land on "spotify-tui".
check("exact app id wins over a longer one containing it",
  logic.windowFor(spotifyTray, [
    { address: "aa", appId: "spotify-tui" },
    { address: "bb", appId: "Spotify" },
  ])?.address === "bb");
// A short class must not match by accident inside a longer name.
check("short app ids only match exactly",
  logic.windowFor({ id: "kittyfoo-tray", title: "", icon: "" }, [{ address: "cc", appId: "kit" }]) === null);

// Pinned apps use their configured class; the config says "spotify", the
// window says "Spotify". The case mismatch is what made a click relaunch it.
check("pinned Spotify finds the Spotify window",
  logic.windowForApp(spotifyPin, windows)?.address === "56462b273980");
check("pinned app with no window finds nothing",
  logic.windowForApp({ ...spotifyPin, wmClass: "obsidian" }, windows) === null);

// One icon per app: a pinned app hides its tray item; duplicates collapse.
const visible = logic.visibleItems([spotifyTray, hermesTray, nmTray], [spotifyPin]);
check("pinned Spotify hides the Spotify tray item",
  visible.length === 2 && visible[0] === hermesTray && visible[1] === nmTray);
check("pinned app's tray item is found for its menu",
  logic.trayItemForApp(spotifyPin, [hermesTray, spotifyTray]) === spotifyTray);
check("pinned app with no tray item has no menu source",
  logic.trayItemForApp({ ...spotifyPin, wmClass: "obsidian", desktopId: "obsidian", icon: "obsidian" },
    [hermesTray, spotifyTray]) === null);
const dup = { id: "spotify-client", title: "spotify", icon: "image://icon/spotify-linux-32" };
check("two tray items for one app draw once",
  logic.visibleItems([spotifyTray, dup, hermesTray], []).length === 2);
check("nothing pinned keeps every distinct tray item",
  logic.visibleItems([spotifyTray, hermesTray, nmTray], []).length === 3);
check("an object model's .values is accepted",
  logic.visibleItems({ values: [hermesTray] }, []).length === 1);
check("no tray items is an empty list", logic.visibleItems(null, [spotifyPin]).length === 0);
// Quickshell's ObjectModel.values is a QML list: indexable with a length, but
// not a JS Array. Rejecting it hid every live tray icon and window.
const qmlList = (...xs) => Object.assign(Object.create(null), xs, { length: xs.length });
check("a QML list (array-like, not an Array) is accepted",
  logic.visibleItems({ values: qmlList(hermesTray, spotifyTray) }, [spotifyPin]).length === 1);
check("Hyprland toplevels as a QML list map to windows",
  logic.windowsFrom({ values: qmlList({ address: "a1", wayland: { appId: "Spotify" } }) }).length === 1);

// The dispatch focuses by address; Hyprland reports it without 0x.
check("focus request adds 0x to a bare address",
  logic.focusRequest("56462b273980") === 'hl.dsp.focus({ window = "address:0x56462b273980" })');
check("focus request keeps an existing 0x",
  logic.focusRequest("0xabc") === 'hl.dsp.focus({ window = "address:0xabc" })');
check("focus request refuses anything but hex", logic.focusRequest('abc" }) x({') === "");

// Hyprland toplevels → plain windows: the Wayland app id, else the IPC class.
check("toplevels map to address and app id",
  JSON.stringify(logic.windowsFrom({ values: [
    { address: "a1", wayland: { appId: "Spotify" } },
    { address: "b2", wayland: null, lastIpcObject: { class: "hermes-chat" } },
  ] })) === '[{"address":"a1","appId":"Spotify"},{"address":"b2","appId":"hermes-chat"}]');

if (failures > 0) {
  console.log(failures + " failed");
  process.exit(1);
}
console.log("ok: tray app logic");
