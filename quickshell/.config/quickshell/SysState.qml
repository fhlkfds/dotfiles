pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Local system metrics.
//
// Everything comes from /proc and /sys reads except disk usage, which needs df.
// Polling only runs while `active` is set, so an unused SysState costs nothing.
//
// hwmon and DRM card indices are NOT stable across boots, so the sensor paths
// are resolved by matching hwmon/name at startup rather than hardcoded.
Singleton {
  id: root

  // Polls only while the clock dashboard is on screen, so a closed dashboard
  // costs nothing. Readings are kept across closes, so reopening shows the last
  // values at once and refreshes them within a second.
  readonly property bool active: DashboardState.panelVisible

  // --- resolved sensor paths -------------------------------------------------

  property string cpuTempPath: ""   // k10temp Tctl, zenpower, or coretemp package
  property string gpuTempPath: ""   // amdgpu temp1_input (edge)
  property string gpuBusyPath: ""   // card*/device/gpu_busy_percent
  property string gpuPowerPath: ""  // amdgpu power1_average, microwatts
  // NVIDIA has no sysfs utilisation, so it goes through nvidia-smi -- but only
  // while the card is awake. On a hybrid laptop the dGPU sits in D3cold, and
  // querying it would wake it up and drain the battery to draw a graph.
  property string nvidiaDevPath: ""
  property string gpuPciId: ""
  property bool nvidiaSmi: false
  property bool nvidiaAwake: false
  property bool gpuAsleep: false

  property bool cpuTempReported: false
  property bool gpuReported: false
  readonly property bool cpuTempAvailable: cpuTempReported
  readonly property bool gpuAvailable: gpuReported

  property string cpuModel: ""
  property string hostname: ""
  property string kernel: ""
  // Prefer the bracketed marketing name lspci carries ("GeForce GTX 1650
  // Mobile / Max-Q", "Radeon RX 6400"), for the vendor actually monitored.
  property string gpuModel: ""
  property var gpuLines: []

  Component.onCompleted: {
    discoverProc.running = true
    namesProc.running = true
  }

  function gpuName(line) {
    const marketing = line.match(/\[([^\]]*(GeForce|Quadro|RTX|GTX|Radeon|Arc)[^\]]*)\]/)
    if (marketing)
      return marketing[1]
    return line.replace(/^.*?controller[^:]*:\s*/, "").replace(/\s*\[[0-9a-f]{4}:[0-9a-f]{4}\].*$/, "")
  }

  function pickGpuModel() {
    for (var i = 0; i < root.gpuLines.length; i++)
      if (root.gpuPciId !== "" && root.gpuLines[i].indexOf(root.gpuPciId + " ") === 0) {
        root.gpuModel = root.gpuName(root.gpuLines[i])
        return
      }
  }
  onGpuPciIdChanged: pickGpuModel()

  Process {
    id: namesProc
    command: ["sh", "-c",
      'grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | sed "s/^ *//"; ' +
      'lspci -Dnn 2>/dev/null | grep -iE "vga|3d"']
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const lines = text.trim().split("\n")
        root.cpuModel = lines[0].trim()
        root.gpuLines = lines.slice(1)
        root.pickGpuModel()
      }
    }
    stderr: StdioCollector {}
  }

  FileView {
    path: "/proc/sys/kernel/hostname"
    onLoaded: root.hostname = text().trim()
  }
  FileView {
    path: "/proc/sys/kernel/osrelease"
    onLoaded: root.kernel = text().trim()
  }

  // --- peripheral battery (UPower) --------------------------------------------
  // This machine has no system battery; the only real one is the mouse. Read
  // natively through UPower rather than shelling out, and hidden entirely when
  // the device is absent -- no invented percentage.
  readonly property var mouseBattery: {
    const list = UPower.devices ? UPower.devices.values : []
    for (var i = 0; i < list.length; i++) {
      const d = list[i]
      if (d && d.isPresent && d.type === UPowerDeviceType.Mouse)
        return d
    }
    return null
  }

  readonly property bool mouseBatteryAvailable: mouseBattery !== null
  // UPower reports percentage as a 0..1 fraction (verified: 0.25 while sysfs
  // capacity read 25), so scale it for display.
  readonly property real mouseBatteryPercent:
    mouseBattery ? mouseBattery.percentage * 100 : 0
  readonly property string mouseBatteryModel: mouseBattery ? mouseBattery.model : ""
  readonly property bool mouseCharging: mouseBattery
    && mouseBattery.state === UPowerDeviceState.Charging

  // False means running on AC, which is always true for this desktop.
  readonly property bool onBattery: UPower.onBattery

  Process {
    id: discoverProc
    command: ["sh", "-c",
      'for h in /sys/class/hwmon/hwmon*; do ' +
      'n=$(cat "$h/name" 2>/dev/null); ' +
      '[ -n "$n" ] && echo "HWMON $n $h"; done; ' +
      'for c in /sys/class/drm/card*/device/gpu_busy_percent; do ' +
      '[ -e "$c" ] || continue; d=${c%/gpu_busy_percent}; ' +
      'echo "GPUBUSY $c $(basename "$(readlink -f "$d")")"; ' +
      'for h in "$d"/hwmon/hwmon*; do ' +
      '[ "$(cat "$h/name" 2>/dev/null)" = amdgpu ] && echo "GPUHWMON $c $h"; done; done; ' +
      'for d in /sys/class/drm/card*/device; do ' +
      '[ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] && echo "NVIDIA $d $(basename "$(readlink -f "$d")")"; done; ' +
      'command -v nvidia-smi >/dev/null 2>&1 && echo NVSMI']
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const lines = text.trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          const p = lines[i].trim().split(/\s+/)
          if (p[0] === "HWMON" && p.length >= 3) {
            // temp1_input is Tctl on k10temp, the package sensor on
            // coretemp, and edge on amdgpu.
            if (p[1] === "k10temp" || p[1] === "zenpower" || p[1] === "coretemp")
              root.cpuTempPath = p[2] + "/temp1_input"
          } else if (p[0] === "GPUBUSY" && p.length >= 3 && root.gpuBusyPath === "") {
            root.gpuBusyPath = p[1]
            root.gpuPciId = p[2]
          } else if (p[0] === "GPUHWMON" && p[1] === root.gpuBusyPath) {
            root.gpuTempPath = p[2] + "/temp1_input"
            root.gpuPowerPath = p[2] + "/power1_average"
          } else if (p[0] === "NVIDIA" && p.length >= 3 && root.nvidiaDevPath === "" && root.gpuBusyPath === "") {
            root.nvidiaDevPath = p[1]
            root.gpuPciId = p[2]
          } else if (p[0] === "NVSMI") {
            root.nvidiaSmi = true
          }
        }
      }
    }
    stderr: StdioCollector {}
  }

  // --- readings --------------------------------------------------------------

  property real cpuPercent: 0
  property bool cpuSeeded: false
  property bool cpuSamplingSeeded: false
  property real memUsedBytes: 0
  property real memTotalBytes: 0
  property real diskUsedBytes: 0
  property real diskTotalBytes: 0
  property real swapUsedBytes: 0
  property real swapTotalBytes: 0
  property real cpuTempC: 0
  property real gpuTempC: 0
  property real gpuPercent: 0
  property real gpuVramUsedBytes: 0
  property real gpuVramTotalBytes: 0
  property real gpuPowerW: -1       // -1: not reported
  property real uptimeSeconds: 0
  property real cpuFreqGhz: 0
  property real loadAvg: 0
  property var coreUsage: []        // 0..1 per logical CPU

  // Network, from /proc/net/dev. The interface is NetworkState's when it has
  // one, otherwise the busiest non-loopback device.
  property string netIface: ""
  property real rxRate: 0           // bytes/s
  property real txRate: 0
  property real rxTotal: 0          // bytes since boot
  property real txTotal: 0

  // Last minute of samples, oldest first, for the dashboard graphs.
  readonly property int historyLength: 60
  property var cpuHistory: []
  property var gpuHistory: []
  property var rxHistory: []
  property var txHistory: []

  function pushHistory(list, v) {
    const out = list.length >= root.historyLength ? list.slice(1) : list.slice()
    out.push(v)
    return out
  }

  readonly property real memFraction: memTotalBytes > 0 ? memUsedBytes / memTotalBytes : 0
  readonly property real diskFraction: diskTotalBytes > 0 ? diskUsedBytes / diskTotalBytes : 0

  // Hardware sensors report millidegrees Celsius; the UI wants Fahrenheit.
  function toF(c) { return c * 9 / 5 + 32 }
  readonly property real cpuTempF: toF(cpuTempC)
  readonly property real gpuTempF: toF(gpuTempC)

  // --- files -----------------------------------------------------------------

  // FileView reloads asynchronously. Parse only completed reads so the UI
  // thread never blocks and the runtime-PM check cannot use stale contents.
  FileView { id: statFile; path: "/proc/stat"; onLoaded: root.parseCpu(text()) }
  FileView { id: memFile; path: "/proc/meminfo"; onLoaded: root.parseMem(text()) }
  FileView {
    id: upFile; path: "/proc/uptime"
    onLoaded: { const v = parseFloat(text()); if (isFinite(v)) root.uptimeSeconds = v }
  }
  FileView {
    id: loadFile; path: "/proc/loadavg"
    onLoaded: { const v = parseFloat(text()); if (isFinite(v)) root.loadAvg = v }
  }
  FileView { id: cpuinfoFile; path: "/proc/cpuinfo"; onLoaded: root.parseFrequency(text()) }
  FileView { id: netFile; path: "/proc/net/dev"; onLoaded: root.parseNet(text()) }
  FileView {
    id: cpuTempFile; path: root.cpuTempPath; printErrors: false
    onLoaded: {
      const v = parseFloat(text())
      root.cpuTempReported = isFinite(v)
      if (root.cpuTempReported) root.cpuTempC = v / 1000
    }
    onLoadFailed: root.cpuTempReported = false
  }
  FileView {
    id: gpuTempFile; path: root.gpuTempPath; printErrors: false
    onLoaded: {
      const v = parseFloat(text())
      root.gpuTempReported = isFinite(v)
      if (root.gpuTempReported) root.gpuTempC = v / 1000
    }
    onLoadFailed: root.gpuTempReported = false
  }
  FileView {
    id: gpuBusyFile; path: root.gpuBusyPath; printErrors: false
    onLoaded: {
      const v = parseFloat(text())
      root.gpuReported = isFinite(v) && v >= 0 && v <= 100
      if (root.gpuReported) {
        root.gpuPercent = v
        root.gpuHistory = root.pushHistory(root.gpuHistory, v / 100)
      }
    }
    onLoadFailed: root.gpuReported = false
  }
  FileView {
    id: gpuPowerFile; path: root.gpuPowerPath; printErrors: false
    onLoaded: { const v = parseFloat(text()); root.gpuPowerW = isFinite(v) ? v / 1e6 : -1 }
    onLoadFailed: root.gpuPowerW = -1
  }
  FileView {
    id: vramUsedFile
    path: root.gpuBusyPath !== "" ? root.gpuBusyPath.replace("gpu_busy_percent", "mem_info_vram_used") : ""
    printErrors: false
    onLoaded: { const v = parseFloat(text()); root.gpuVramUsedBytes = isFinite(v) ? v : 0 }
    onLoadFailed: root.gpuVramUsedBytes = 0
  }
  FileView {
    id: vramTotalFile
    path: root.gpuBusyPath !== "" ? root.gpuBusyPath.replace("gpu_busy_percent", "mem_info_vram_total") : ""
    printErrors: false
    onLoaded: { const v = parseFloat(text()); root.gpuVramTotalBytes = isFinite(v) ? v : 0 }
    onLoadFailed: root.gpuVramTotalBytes = 0
  }
  FileView {
    id: nvidiaPmFile
    path: root.nvidiaDevPath !== "" ? root.nvidiaDevPath + "/power/runtime_status" : ""
    printErrors: false
    onLoaded: {
      const state = text().trim()
      root.nvidiaAwake = state === "active"
      root.gpuAsleep = state === "suspended" || state === "suspending"
      if (state !== "active") root.clearNvidia()
      // Unknown/failed PM reads are not permission to wake the card.
      if (root.active && state === "active" && !nvidiaProc.running)
        nvidiaProc.running = true
    }
    onLoadFailed: { root.nvidiaAwake = false; root.gpuAsleep = false; root.clearNvidia() }
  }

  // Previous /proc/stat counters, as [total, idle] per line: index 0 is the
  // aggregate "cpu" line, 1.. the individual cores.
  property var lastStat: []

  function parseCpu(text) {
    if (!root.active) return
    const lines = text.split("\n")
    const next = []
    const cores = []
    for (var l = 0; l < lines.length; l++) {
      if (lines[l].indexOf("cpu") !== 0)
        break
      const f = lines[l].trim().split(/\s+/).slice(1).map(Number)
      if (f.length < 5 || !f.slice(0, 8).every(isFinite))
        continue
      var total = 0
      // guest and guest_nice are already included in user and nice.
      for (var i = 0; i < Math.min(8, f.length); i++)
        total += f[i]
      const idle = f[3] + f[4]   // idle + iowait
      next.push([total, idle])

      const prev = root.lastStat[next.length - 1]
      const dt = prev ? total - prev[0] : 0
      const busy = dt > 0 ? Math.max(0, Math.min(1, 1 - (idle - prev[1]) / dt)) : 0
      if (l === 0) {
        if (dt > 0) {
          root.cpuPercent = busy * 100
          root.cpuSeeded = true
          root.cpuSamplingSeeded = true
          root.cpuHistory = root.pushHistory(root.cpuHistory, busy)
        }
      } else {
        cores.push(busy)
      }
    }
    if (root.lastStat.length > 0)
      root.coreUsage = cores
    root.lastStat = next
  }

  function parseFrequency(text) {
    const mhz = text.match(/^cpu MHz\s*:\s*[\d.]+/gm)
    if (mhz && mhz.length > 0) {
      var sum = 0
      for (var i = 0; i < mhz.length; i++)
        sum += parseFloat(mhz[i].split(":")[1])
      root.cpuFreqGhz = sum / mhz.length / 1000
    }
  }

  property real lastNetRx: -1
  property real lastNetTx: -1
  property real lastNetMs: 0

  function parseNet(text) {
    if (!root.active) return
    const rows = text.split("\n").slice(2)
    const wanted = NetworkState.iface
    var pick = null
    for (var i = 0; i < rows.length; i++) {
      const m = rows[i].match(/^\s*([^:\s]+):\s*(.*)$/)
      if (!m || m[1] === "lo")
        continue
      const f = m[2].trim().split(/\s+/).map(Number)
      const row = { name: m[1], rx: f[0], tx: f[8] }
      if (f.length < 9 || !isFinite(row.rx) || !isFinite(row.tx))
        continue
      if (m[1] === wanted) { pick = row; break }
      if (!pick || row.rx + row.tx > pick.rx + pick.tx)
        pick = row
    }
    if (!pick || pick.name !== root.netIface) {
      root.rxRate = 0; root.txRate = 0
      root.rxHistory = []; root.txHistory = []
      root.lastNetRx = -1
    }
    if (!pick) {
      root.netIface = ""; root.rxTotal = 0; root.txTotal = 0
      return
    }
    const now = Date.now()
    if (pick.name === root.netIface && root.lastNetRx >= 0 && now > root.lastNetMs) {
      const secs = (now - root.lastNetMs) / 1000
      root.rxRate = Math.max(0, (pick.rx - root.lastNetRx) / secs)
      root.txRate = Math.max(0, (pick.tx - root.lastNetTx) / secs)
      root.rxHistory = root.pushHistory(root.rxHistory, root.rxRate)
      root.txHistory = root.pushHistory(root.txHistory, root.txRate)
    }
    root.netIface = pick.name
    root.rxTotal = pick.rx
    root.txTotal = pick.tx
    root.lastNetRx = pick.rx
    root.lastNetTx = pick.tx
    root.lastNetMs = now
  }

  function parseMem(t) {
    const total = t.match(/MemTotal:\s+(\d+)/)
    const avail = t.match(/MemAvailable:\s+(\d+)/)
    if (total && avail) {
      root.memTotalBytes = parseFloat(total[1]) * 1024
      root.memUsedBytes = root.memTotalBytes - parseFloat(avail[1]) * 1024
    }
    const swapTotal = t.match(/SwapTotal:\s+(\d+)/)
    const swapFree = t.match(/SwapFree:\s+(\d+)/)
    if (swapTotal && swapFree) {
      root.swapTotalBytes = parseFloat(swapTotal[1]) * 1024
      root.swapUsedBytes = root.swapTotalBytes - parseFloat(swapFree[1]) * 1024
    }
  }

  function sampleTemps() {
    if (root.cpuTempPath !== "") cpuTempFile.reload()
    if (root.gpuBusyPath !== "") {
      gpuBusyFile.reload()
      if (root.gpuTempPath !== "") gpuTempFile.reload()
      if (root.gpuPowerPath !== "") gpuPowerFile.reload()
      vramUsedFile.reload()
      vramTotalFile.reload()
    } else if (root.nvidiaSmi && root.nvidiaDevPath !== "") {
      nvidiaPmFile.reload()
    }
  }

  function clearNvidia() {
    root.gpuReported = false
    root.gpuTempReported = false
    root.gpuVramUsedBytes = 0
    root.gpuVramTotalBytes = 0
    root.gpuPowerW = -1
  }

  function parseNvidia(text) {
    root.clearNvidia()
    if (!root.nvidiaAwake) return
    const f = text.trim().split("\n")[0].split(",").map(s => parseFloat(s))
    if (f.length < 5 || !isFinite(f[0]) || f[0] < 0 || f[0] > 100)
      return
    root.gpuReported = true
    root.gpuPercent = f[0]
    root.gpuHistory = root.pushHistory(root.gpuHistory, f[0] / 100)
    root.gpuTempReported = isFinite(f[1])
    if (root.gpuTempReported) root.gpuTempC = f[1]
    if (isFinite(f[2]) && isFinite(f[3]) && f[3] > 0) {
      root.gpuVramUsedBytes = f[2] * 1048576
      root.gpuVramTotalBytes = f[3] * 1048576
    }
    root.gpuPowerW = isFinite(f[4]) ? f[4] : -1
  }

  Process {
    id: nvidiaProc
    command: ["timeout", "2s", "nvidia-smi", "--id=" + root.gpuPciId,
      "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
      "--format=csv,noheader,nounits"]
    stdout: StdioCollector { onStreamFinished: root.parseNvidia(text) }
    stderr: StdioCollector {}
    onExited: function (code) { if (code !== 0) root.clearNvidia() }
  }

  property bool gpuTempReported: false
  readonly property bool gpuTempAvailable: gpuTempReported && !gpuAsleep

  // Fast metrics: only while the dashboard is open.
  // The first CPU reading needs two samples, so the second comes quickly.
  Timer {
    interval: root.cpuSamplingSeeded ? 1000 : 250
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      statFile.reload()
      memFile.reload()
      upFile.reload()
      root.sampleTemps()
      loadFile.reload()
      cpuinfoFile.reload()
      netFile.reload()
    }
  }

  // Disk is the only external command, so it polls slowly.
  Timer {
    interval: 30000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: dfProc.running = true
  }

  Process {
    id: dfProc
    command: ["df", "-B1", "--output=used,size", "/"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const rows = text.trim().split("\n")
        if (rows.length < 2)
          return
        const p = rows[rows.length - 1].trim().split(/\s+/)
        const used = parseFloat(p[0])
        const size = parseFloat(p[1])
        if (!isNaN(used) && !isNaN(size) && size > 0) {
          root.diskUsedBytes = used
          root.diskTotalBytes = size
        }
      }
    }
    stderr: StdioCollector {}
  }

  // Reset the delta baselines when the panel closes, so the first reading
  // after reopening is not computed against a stale sample. The readings
  // themselves stay on screen until fresh ones arrive.
  onActiveChanged: {
    if (!active) {
      root.lastStat = []
      root.cpuSamplingSeeded = false
      root.lastNetRx = -1
    }
  }

  // --- formatting ------------------------------------------------------------

  function fmtBytes(b) {
    if (!isFinite(b) || b <= 0)
      return "0 B"
    const u = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    var v = b
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
    return (v >= 10 ? Math.round(v) : v.toFixed(1)) + " " + u[i]
  }

  // "14.1 GiB", matching how the dashboard prints memory.
  function fmtGiB(b) {
    return (isFinite(b) && b > 0 ? b / 1073741824 : 0).toFixed(1) + " GiB"
  }

  function fmtRate(b) {
    return fmtBytes(b) + "/s"
  }

  function fmtUptime(s) {
    const d = Math.floor(s / 86400)
    const h = Math.floor((s % 86400) / 3600)
    const m = Math.floor((s % 3600) / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }
}
