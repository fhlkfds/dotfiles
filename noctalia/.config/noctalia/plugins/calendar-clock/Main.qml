import QtQuick
import Quickshell.Io
import qs.Commons

// Headless singleton for the Calendar Clock plugin.
//
// Qt 6.11's V4 engine has no Intl, and Date.toLocaleString() silently ignores the
// {timeZone} option, so there is no in-engine way to render another IANA zone.
// Instead we resolve the zone's UTC offset once via `TZ=<zone> date +%z` and shift
// the Date object, then let the normal local formatter render it. Every consumer
// reads displayTime so the label, tooltip and calendar can never disagree.
Item {
  id: root

  property var pluginApi: null

  // ── Static tables ─────────────────────────────────────────────────────────
  // "local" is a sentinel meaning "shift by nothing", so resetting to local really
  // tracks the system clock rather than pinning a hardcoded Chicago offset.
  readonly property var zones: ["local", "America/New_York", "America/Denver", "America/Los_Angeles", "America/Phoenix", "UTC"]

  readonly property var formats: ["h:mm AP", "HH:mm", "ddd, MMM d", "yyyy-MM-dd"]

  // ── Settings-backed state ─────────────────────────────────────────────────
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})
  readonly property string format: pluginApi?.pluginSettings?.format ?? defaults.format ?? "h:mm AP"
  readonly property string timezone: pluginApi?.pluginSettings?.timezone ?? defaults.timezone ?? "local"
  readonly property string tooltipFormat: pluginApi?.pluginSettings?.tooltipFormat ?? defaults.tooltipFormat ?? "HH:mm ddd, MMM dd"
  readonly property string clockColor: pluginApi?.pluginSettings?.clockColor ?? defaults.clockColor ?? "none"

  readonly property bool isLocal: root.timezone === "local"

  // Minutes east of UTC for the selected zone (America/New_York in summer = -240).
  // Seeded from the cached value so switching back to a zone doesn't flash local time.
  property int tzOffsetMinutes: pluginApi?.pluginSettings?.cachedOffset ?? 0

  // getTimezoneOffset() is minutes *behind* UTC (Chicago CDT = +300), so adding it
  // converts "offset from UTC" into "offset from the local zone".
  readonly property int offsetDeltaMinutes: root.isLocal ? 0 : (root.tzOffsetMinutes + Time.now.getTimezoneOffset())

  readonly property var displayTime: root.isLocal ? Time.now : new Date(Time.now.getTime() + root.offsetDeltaMinutes * 60000)

  // ── Helpers ───────────────────────────────────────────────────────────────
  function isKnownZone(zone) {
    return root.zones.indexOf(zone) !== -1;
  }

  function zoneLabel(zone) {
    if (zone === "local") {
      return pluginApi?.tr("timezones.local") ?? "Local";
    }
    // IANA identifiers are not translated.
    return zone;
  }

  // ── Mutators (right-click cycle, middle-click menu) ────────────────────────
  function cycleFormat() {
    if (!pluginApi)
      return;
    // indexOf returns -1 for a hand-edited/unknown value, which lands us on index 0.
    var next = root.formats[(root.formats.indexOf(root.format) + 1) % root.formats.length];
    pluginApi.pluginSettings.format = next;
    pluginApi.saveSettings();
  }

  function setTimezone(zone) {
    if (!pluginApi || !root.isKnownZone(zone))
      return;
    pluginApi.pluginSettings.timezone = zone;
    if (zone === "local") {
      root.tzOffsetMinutes = 0;
      pluginApi.pluginSettings.cachedOffset = 0;
    }
    pluginApi.saveSettings();
  }

  // ── Offset resolution ─────────────────────────────────────────────────────
  function resolveOffset() {
    if (root.isLocal) {
      root.tzOffsetMinutes = 0;
      return;
    }
    // Guard the shell-out: only ever interpolate a zone from the fixed table above.
    if (!root.isKnownZone(root.timezone)) {
      Logger.w("CalendarClock", "Ignoring unknown timezone:", root.timezone);
      return;
    }
    if (tzProbe.running)
      return;
    tzProbe.command = ["sh", "-c", "TZ='" + root.timezone + "' date +%z"];
    tzProbe.running = true;
  }

  function cacheOffset() {
    if (!pluginApi)
      return;
    if (pluginApi.pluginSettings.cachedOffset === root.tzOffsetMinutes)
      return;
    pluginApi.pluginSettings.cachedOffset = root.tzOffsetMinutes;
    pluginApi.saveSettings();
  }

  onTimezoneChanged: root.resolveOffset()

  Component.onCompleted: root.resolveOffset()

  Process {
    id: tzProbe

    running: false
    stdout: StdioCollector {}

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.w("CalendarClock", "Failed to resolve offset for", root.timezone, "exit", exitCode);
        return;
      }
      var out = String(tzProbe.stdout.text || "").trim();
      var m = out.match(/^([+-])(\d{2})(\d{2})$/);
      if (!m) {
        Logger.w("CalendarClock", "Unparseable offset for", root.timezone + ":", out);
        return;
      }
      var mins = parseInt(m[2], 10) * 60 + parseInt(m[3], 10);
      root.tzOffsetMinutes = (m[1] === "-") ? -mins : mins;
      root.cacheOffset();
    }
  }

  // Catches DST transitions without polling the clock every second.
  Timer {
    interval: 15 * 60 * 1000
    repeat: true
    running: !root.isLocal
    onTriggered: root.resolveOffset()
  }

  // The offset may have moved while the machine was asleep.
  Connections {
    target: Time

    function onResumed() {
      root.resolveOffset();
    }
  }
}
