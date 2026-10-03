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
  property bool nvidiaSmi: false
  property bool gpuAsleep: false

  readonly property bool cpuTempAvailable: cpuTempPath !== ""
  readonly property bool gpuAvailable: gpuBusyPath !== "" || (nvidiaSmi && nvidiaDevPath !== "")

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
    const vendor = root.gpuBusyPath !== "" ? /AMD|ATI/ : (root.nvidiaDevPath !== "" ? /NVIDIA/ : /./)
    for (var i = 0; i < root.gpuLines.length; i++)
      if (vendor.test(root.gpuLines[i])) {
        root.gpuModel = root.gpuName(root.gpuLines[i])
        return
      }
  }
  onGpuBusyPathChanged: pickGpuModel()
  onNvidiaDevPathChanged: pickGpuModel()

  Process {
    id: namesProc
    command: ["sh", "-c",
      'grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | sed "s/^ *//"; ' +
      'lspci -nn 2>/dev/null | grep -iE "vga|3d"']
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
      '[ -e "$c" ] && echo "GPUBUSY $c"; done; ' +
      'for d in /sys/class/drm/card*/device; do ' +
      '[ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] && echo "NVIDIA $d"; done; ' +
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
            else if (p[1] === "amdgpu") {
              root.gpuTempPath = p[2] + "/temp1_input"
              root.gpuPowerPath = p[2] + "/power1_average"
            }
          } else if (p[0] === "GPUBUSY" && p.length >= 2) {
            root.gpuBusyPath = p[1]
          } else if (p[0] === "NVIDIA" && p.length >= 2 && root.nvidiaDevPath === "") {
            root.nvidiaDevPath = p[1]
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

  FileView { id: statFile; path: "/proc/stat" }
  FileView { id: memFile; path: "/proc/meminfo" }
  FileView { id: upFile; path: "/proc/uptime" }
  FileView { id: loadFile; path: "/proc/loadavg" }
  FileView { id: cpuinfoFile; path: "/proc/cpuinfo" }
  FileView { id: netFile; path: "/proc/net/dev" }
  FileView { id: cpuTempFile; path: root.cpuTempPath }
  FileView { id: gpuTempFile; path: root.gpuTempPath }
  FileView { id: gpuBusyFile; path: root.gpuBusyPath }
  FileView { id: gpuPowerFile; path: root.gpuPowerPath; printErrors: false }
  FileView {
    id: vramUsedFile
    path: root.gpuBusyPath !== "" ? root.gpuBusyPath.replace("gpu_busy_percent", "mem_info_vram_used") : ""
    printErrors: false
  }
  FileView {
    id: vramTotalFile
    path: root.gpuBusyPath !== "" ? root.gpuBusyPath.replace("gpu_busy_percent", "mem_info_vram_total") : ""
    printErrors: false
  }
  FileView {
    id: nvidiaPmFile
    path: root.nvidiaDevPath !== "" ? root.nvidiaDevPath + "/power/runtime_status" : ""
    printErrors: false
  }

  // Previous /proc/stat counters, as [total, idle] per line: index 0 is the
  // aggregate "cpu" line, 1.. the individual cores.
  property var lastStat: []

  function sampleCpu() {
    statFile.reload()
    const lines = statFile.text().split("\n")
    const next = []
    const cores = []
    for (var l = 0; l < lines.length; l++) {
      if (lines[l].indexOf("cpu") !== 0)
        break
      const f = lines[l].trim().split(/\s+/).slice(1).map(Number)
      if (f.length < 5)
        continue
      var total = 0
      for (var i = 0; i < f.length; i++)
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

  function sampleLoad() {
    loadFile.reload()
    const v = parseFloat(loadFile.text())
    if (!isNaN(v))
      root.loadAvg = v
    cpuinfoFile.reload()
    const mhz = cpuinfoFile.text().match(/^cpu MHz\s*:\s*[\d.]+/gm)
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

  function sampleNet() {
    netFile.reload()
    const rows = netFile.text().split("\n").slice(2)
    const wanted = NetworkState.iface
    var pick = null
    for (var i = 0; i < rows.length; i++) {
      const m = rows[i].match(/^\s*([^:\s]+):\s*(.*)$/)
      if (!m || m[1] === "lo")
        continue
      const f = m[2].trim().split(/\s+/).map(Number)
      const row = { name: m[1], rx: f[0], tx: f[8] }
      if (m[1] === wanted) { pick = row; break }
      if (!pick || row.rx + row.tx > pick.rx + pick.tx)
        pick = row
    }
    if (!pick)
      return
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

  function sampleMem() {
    memFile.reload()
    const t = memFile.text()
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

  function sampleUptime() {
    upFile.reload()
    const v = parseFloat(upFile.text().trim().split(/\s+/)[0])
    if (!isNaN(v))
      root.uptimeSeconds = v
  }

  function sampleTemps() {
    if (root.cpuTempPath !== "") {
      cpuTempFile.reload()
      const c = parseFloat(cpuTempFile.text())
      if (!isNaN(c))
        root.cpuTempC = c / 1000
    }
    if (root.gpuTempPath !== "") {
      gpuTempFile.reload()
      const g = parseFloat(gpuTempFile.text())
      if (!isNaN(g))
        root.gpuTempC = g / 1000
    }
    if (root.gpuBusyPath !== "") {
      gpuBusyFile.reload()
      const b = parseFloat(gpuBusyFile.text())
      if (!isNaN(b)) {
        root.gpuPercent = b
        root.gpuHistory = root.pushHistory(root.gpuHistory, b / 100)
      }
      vramUsedFile.reload()
      vramTotalFile.reload()
      const used = parseFloat(vramUsedFile.text())
      const vtotal = parseFloat(vramTotalFile.text())
      if (!isNaN(used) && !isNaN(vtotal)) {
        root.gpuVramUsedBytes = used
        root.gpuVramTotalBytes = vtotal
      }
      if (root.gpuPowerPath !== "") {
        gpuPowerFile.reload()
        const uw = parseFloat(gpuPowerFile.text())
        root.gpuPowerW = isNaN(uw) ? -1 : uw / 1e6
      }
    } else if (root.nvidiaSmi && root.nvidiaDevPath !== "") {
      nvidiaPmFile.reload()
      root.gpuAsleep = nvidiaPmFile.text().trim() === "suspended"
      if (!root.gpuAsleep && !nvidiaProc.running)
        nvidiaProc.running = true
    }
  }

  Process {
    id: nvidiaProc
    command: ["nvidia-smi",
      "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
      "--format=csv,noheader,nounits"]
    stdout: StdioCollector {
      onStreamFinished: {
        const f = text.trim().split("\n")[0].split(",").map(s => parseFloat(s))
        if (f.length < 5 || isNaN(f[0]))
          return
        root.gpuPercent = f[0]
        root.gpuHistory = root.pushHistory(root.gpuHistory, f[0] / 100)
        if (!isNaN(f[1])) {
          root.gpuTempC = f[1]
          root.gpuTempReported = true
        }
        root.gpuVramUsedBytes = f[2] * 1048576
        root.gpuVramTotalBytes = f[3] * 1048576
        root.gpuPowerW = isNaN(f[4]) ? -1 : f[4]
      }
    }
    stderr: StdioCollector {}
  }

  // amdgpu reads its temperature from hwmon; nvidia-smi reports it directly.
  property bool gpuTempReported: false
  readonly property bool gpuTempAvailable: (gpuTempPath !== "" || gpuTempReported) && !gpuAsleep

  // Fast metrics: only while the dashboard is open.
  // The first CPU reading needs two samples, so the second comes quickly.
  Timer {
    interval: root.cpuSeeded ? 1000 : 250
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.sampleCpu()
      root.sampleMem()
      root.sampleUptime()
      root.sampleTemps()
      root.sampleLoad()
      root.sampleNet()
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
