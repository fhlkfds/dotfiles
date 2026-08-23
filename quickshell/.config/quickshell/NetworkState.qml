pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property bool panelVisible: false
  // Connector name of the screen whose bar opened the panel. Each bar
  // instance builds its own popup, so without this the panel would try to
  // open on every monitor at once instead of the one that was clicked.
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
  }

  property string connType: "none" // "ethernet" | "wifi" | "none"
  property string iface: ""
  property string ssid: ""
  property int signalPct: 0

  property string ipAddress: "-"
  property string gateway: "-"

  property real pingMs: -1
  property real packetLossPct: -1

  property real rxRate: 0 // bytes/sec
  property real txRate: 0
  property real rxTotal: 0 // cumulative bytes since iface came up
  property real txTotal: 0
  property real _lastRx: -1
  property real _lastTx: -1

  property bool dnsChanging: false
  property string dnsError: ""
  property string activeProviderId: "" // "dhcp" | "quad9" | "cloudflare" | "" (unknown/custom)
  property string customDnsIp: ""

  readonly property var dnsProviders: [
    { id: "dhcp", label: "DHCP", ip: "" },
    { id: "quad9", label: "Quad9", ip: "9.9.9.9 149.112.112.112" },
    { id: "cloudflare", label: "Cloudflare", ip: "1.1.1.1 1.0.0.1" }
  ]

  readonly property var ipToProvider: ({
    "9.9.9.9": "quad9", "149.112.112.112": "quad9",
    "1.1.1.1": "cloudflare", "1.0.0.1": "cloudflare"
  })

  readonly property var ifaceRegex: /^[a-zA-Z0-9_.:-]+$/
  readonly property var ipRegex: /^(\d{1,3}\.){3}\d{1,3}$/

  function isValidIp(ip) {
    if (!ipRegex.test(ip))
      return false
    const parts = ip.split(".")
    for (let i = 0; i < parts.length; i++) {
      const n = parseInt(parts[i], 10)
      if (n < 0 || n > 255)
        return false
    }
    return true
  }

  function validateDnsInput(s) {
    const trimmed = s.trim()
    if (trimmed === "")
      return true
    const parts = trimmed.split(/\s+/)
    if (parts.length > 2)
      return false
    return parts.every(isValidIp)
  }

  function formatBytes(n) {
    if (!(n >= 0))
      return "-"
    if (n < 1024)
      return n.toFixed(0) + " B"
    if (n < 1024 * 1024)
      return (n / 1024).toFixed(1) + " KB"
    if (n < 1024 * 1024 * 1024)
      return (n / (1024 * 1024)).toFixed(1) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
  }

  function updateDnsState(rawDns) {
    const tokens = rawDns.trim().split(/\s+/).filter(t => t.length > 0)
    if (tokens.length === 0) {
      activeProviderId = "dhcp"
      return
    }
    for (let i = 0; i < tokens.length; i++) {
      const id = ipToProvider[tokens[i]]
      if (id) {
        activeProviderId = id
        return
      }
    }
    activeProviderId = "" // unknown/custom-from-outside
  }

  // --- connection type + active device ---
  Process {
    id: connProc
    command: ["sh", "-c", "nmcli -t -f TYPE,DEVICE connection show --active 2>/dev/null | head -n 1"]
    stdout: StdioCollector {
      onTextChanged: {
        const parts = text.trim().split(":")
        const type = parts[0] || ""
        const dev = parts[1] || ""
        root.iface = root.ifaceRegex.test(dev) ? dev : ""
        if (type.indexOf("wireless") !== -1)
          root.connType = "wifi"
        else if (type !== "")
          root.connType = "ethernet"
        else
          root.connType = "none"
      }
    }
  }

  Process {
    id: wifiProc
    command: ["sh", "-c", "nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list 2>/dev/null | grep '^\\*' | head -n 1"]
    stdout: StdioCollector {
      onTextChanged: {
        const line = text.trim()
        if (line === "")
          return
        const parts = line.split(":")
        root.signalPct = parseInt(parts[1], 10) || 0
        root.ssid = parts.slice(2).join(":")
      }
    }
  }

  Process {
    id: ipProc
    stdout: StdioCollector {
      onTextChanged: {
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          if (line.startsWith("IP4.ADDRESS")) {
            const v = line.split(":").slice(1).join(":").trim()
            root.ipAddress = v.split("/")[0] || "-"
          } else if (line.startsWith("IP4.GATEWAY")) {
            const v = line.split(":").slice(1).join(":").trim()
            root.gateway = v !== "" ? v : "-"
          }
        }
      }
    }
  }

  Process {
    id: dnsCheckProc
    stdout: StdioCollector {
      onTextChanged: {
        const lines = text.split("\n").filter(l => l.startsWith("IP4.DNS"))
        const ips = lines.map(l => l.split(":").slice(1).join(":").trim()).filter(v => v !== "")
        root.updateDnsState(ips.join(" "))
      }
    }
  }

  function refreshConnection() {
    connProc.running = true
  }

  function refreshIfaceDetails() {
    if (root.iface === "")
      return
    ipProc.command = ["sh", "-c", "nmcli -t -f IP4.ADDRESS,IP4.GATEWAY dev show " + root.iface + " 2>/dev/null"]
    ipProc.running = true
    dnsCheckProc.command = ["sh", "-c", "nmcli -t -f IP4.DNS dev show " + root.iface + " 2>/dev/null"]
    dnsCheckProc.running = true
    if (root.connType === "wifi")
      wifiProc.running = true
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshConnection()
  }

  onIfaceChanged: {
    _lastRx = -1
    _lastTx = -1
    refreshIfaceDetails()
  }
  onConnTypeChanged: refreshIfaceDetails()

  // --- ping + packet loss ---
  Process {
    id: pingProc
    command: ["sh", "-c", "ping -c 3 -W 1 google.com 2>/dev/null"]
    stdout: StdioCollector {
      onTextChanged: {
        const lossMatch = text.match(/([\d.]+)%\s*packet loss/)
        if (lossMatch)
          root.packetLossPct = parseFloat(lossMatch[1])
        const rttMatch = text.match(/=\s*[\d.]+\/([\d.]+)\/[\d.]+/)
        if (rttMatch)
          root.pingMs = parseFloat(rttMatch[1])
        else if (lossMatch && parseFloat(lossMatch[1]) >= 100)
          root.pingMs = -1
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: pingProc.running = true
  }

  // --- rx/tx throughput + cumulative totals ---
  FileView {
    id: rxFile
    path: root.iface !== "" ? "/sys/class/net/" + root.iface + "/statistics/rx_bytes" : ""
    watchChanges: false
  }

  FileView {
    id: txFile
    path: root.iface !== "" ? "/sys/class/net/" + root.iface + "/statistics/tx_bytes" : ""
    watchChanges: false
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (root.iface === "")
        return
      rxFile.reload()
      txFile.reload()
      const rx = parseFloat(rxFile.text())
      const tx = parseFloat(txFile.text())
      if (!isNaN(rx)) {
        if (root._lastRx >= 0)
          root.rxRate = Math.max(0, rx - root._lastRx)
        root._lastRx = rx
        root.rxTotal = rx
      }
      if (!isNaN(tx)) {
        if (root._lastTx >= 0)
          root.txRate = Math.max(0, tx - root._lastTx)
        root._lastTx = tx
        root.txTotal = tx
      }
    }
  }

  // --- DNS switching (mirrors noctalia's dns-switcher plugin pattern) ---
  function applyDns(providerId) {
    if (dnsChanging)
      return

    let ips = ""
    if (providerId === "custom") {
      ips = customDnsIp.trim()
      if (ips === "" || !validateDnsInput(ips)) {
        dnsError = "Invalid IP address"
        return
      }
    } else {
      const preset = dnsProviders.find(p => p.id === providerId)
      ips = preset ? preset.ip : ""
    }

    const safeIps = ips.replace(/[^0-9. ]/g, "")
    dnsChanging = true
    dnsError = ""

    let cmd
    if (safeIps === "") {
      cmd = "CON=$(nmcli -t -f NAME connection show --active | head -n 1); " +
            "if [ -z \"$CON\" ]; then exit 1; fi; " +
            "nmcli con mod \"$CON\" ipv4.dns \"\" ipv4.ignore-auto-dns no; " +
            "nmcli con up \"$CON\""
    } else {
      cmd = "CON=$(nmcli -t -f NAME connection show --active | head -n 1); " +
            "if [ -z \"$CON\" ]; then exit 1; fi; " +
            "nmcli con mod \"$CON\" ipv4.dns \"" + safeIps + "\" ipv4.ignore-auto-dns yes; " +
            "nmcli con up \"$CON\""
    }

    dnsApplyProc.command = ["pkexec", "sh", "-c", cmd]
    dnsApplyProc.running = true
  }

  Process {
    id: dnsApplyProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: dnsApplyStderr }
    onExited: function(code) {
      root.dnsChanging = false
      if (code !== 0)
        root.dnsError = "Failed to apply DNS"
      root.refreshIfaceDetails()
    }
  }

  // --- launch nmtui in a terminal for wifi scan/connect ---
  Process {
    id: nmtuiProc
    command: ["kitty", "-e", "nmtui"]
  }

  function openNmtui() {
    nmtuiProc.running = true
  }
}
