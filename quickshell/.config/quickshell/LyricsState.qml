pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Lyrics from LRCLIB (lrclib.net) -- a free, public, no-auth API purpose-built
// for synced lyrics. It is the only provider used, deliberately:
//
//   * Spotify has never exposed lyrics through its Web API; the desktop client
//     fetches them from Musixmatch via an undocumented internal endpoint that
//     needs a client token. Using it would mean an unofficial API and a ToS
//     violation.
//   * Genius's official API returns metadata and URLs but not lyrics text, and
//     carries no timestamps at all, so synced lyrics are impossible from it.
//
// Word-level (karaoke) timing is therefore out of reach and is not faked.
Singleton {
  id: root

  // Parsed synced lines: [{ ms, text }], sorted by ms. Blank lines are kept so
  // the highlight correctly sits on a gap during instrumental breaks.
  property var lines: []
  property string plainText: ""

  // idle | loading | synced | plain | notfound | error
  property string status: "idle"

  // Monotonic request id. A response whose id no longer matches is discarded,
  // so a slow reply for a previous track cannot overwrite the current one.
  property int requestSeq: 0
  property string inFlightKey: ""

  // key -> { lines, plainText, status }. Negative results are cached too, so a
  // track with no lyrics is not re-requested on every position tick.
  property var cache: ({})
  property var cacheOrder: []
  readonly property int cacheLimit: 32

  readonly property string userAgent: "quickshell-media-widget/0.1"

  // --- active line -----------------------------------------------------------

  readonly property int activeIndex: {
    if (root.status !== "synced" || root.lines.length === 0)
      return -1
    const posMs = MediaState.effectivePosition * 1000
    var lo = 0
    var hi = root.lines.length - 1
    var ans = -1
    while (lo <= hi) {
      const mid = (lo + hi) >> 1
      if (root.lines[mid].ms <= posMs) {
        ans = mid
        lo = mid + 1
      } else {
        hi = mid - 1
      }
    }
    return ans
  }

  // --- loading ---------------------------------------------------------------

  Connections {
    target: MediaState
    function onTrackKeyChanged() { root.load() }
  }

  Component.onCompleted: root.load()

  function load() {
    root.requestSeq++

    // Cancel in-flight work. Killing a Process makes it exit non-zero
    // asynchronously, so each process swallows exactly one exit after a cancel
    // (see onExited) -- otherwise that stale exit would be reported as a
    // failure of the request that replaced it.
    if (getProc.running) {
      getProc.cancelled = true
      getProc.running = false
    }
    if (searchProc.running) {
      searchProc.cancelled = true
      searchProc.running = false
    }
    loadTimer.stop()

    const key = MediaState.trackKey
    if (key === "") {
      root.applyResult({ lines: [], plainText: "", status: "idle" })
      return
    }

    // Cache hits are applied straight away -- no request, no delay.
    if (root.cache[key] !== undefined) {
      root.applyResult(root.cache[key])
      return
    }

    root.lines = []
    root.plainText = ""
    root.status = "loading"
    root.inFlightKey = key
    // Debounced: skipping through several tracks fires one request for the
    // track you land on, instead of one per track that is then cancelled.
    loadTimer.restart()
  }

  Timer {
    id: loadTimer
    interval: 350
    repeat: false
    onTriggered: root.doLoad()
  }

  function doLoad() {
    if (MediaState.trackKey !== root.inFlightKey || root.inFlightKey === "")
      return
    getProc.command = ["curl", "-sS", "-G", "--max-time", "10",
      "-H", "User-Agent: " + root.userAgent,
      "--data-urlencode", "artist_name=" + MediaState.trackArtist,
      "--data-urlencode", "track_name=" + MediaState.trackTitle,
      "--data-urlencode", "album_name=" + MediaState.trackAlbum,
      "--data-urlencode", "duration=" + Math.round(MediaState.length),
      "https://lrclib.net/api/get"]
    getProc.launchSeq = root.requestSeq
    getProc.running = true
  }

  function applyResult(res) {
    root.lines = res.lines
    root.plainText = res.plainText
    root.status = res.status
  }

  function remember(key, res) {
    const c = root.cache
    c[key] = res
    const order = root.cacheOrder
    order.push(key)
    while (order.length > root.cacheLimit) {
      const old = order.shift()
      if (old !== key)
        delete c[old]
    }
    root.cache = c
    root.cacheOrder = order
  }

  // Turns an LRCLIB payload into a result object.
  function resultFrom(obj) {
    if (obj && obj.syncedLyrics) {
      const parsed = root.parseLrc(obj.syncedLyrics)
      if (parsed.length > 0)
        return { lines: parsed, plainText: obj.plainLyrics || "", status: "synced" }
    }
    if (obj && obj.plainLyrics)
      return { lines: [], plainText: obj.plainLyrics, status: "plain" }
    return { lines: [], plainText: "", status: "notfound" }
  }

  Process {
    id: getProc
    // Request id this process was started for.
    property int launchSeq: -1
    // Set when we kill the process; its resulting exit is not a real failure.
    property bool cancelled: false
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        if (getProc.launchSeq !== root.requestSeq)
          return
        var obj = null
        try {
          obj = JSON.parse(text)
        } catch (e) {
          root.finish({ lines: [], plainText: "", status: "error" })
          return
        }
        // /api/get answers a miss with 404 + {"name":"TrackNotFound"}.
        if (obj && (obj.statusCode === 404 || obj.name === "TrackNotFound")) {
          root.startSearch()
          return
        }
        const res = root.resultFrom(obj)
        if (res.status === "notfound")
          root.startSearch()
        else
          root.finish(res)
      }
    }
    stderr: StdioCollector { id: getErr }
    onExited: function (code) {
      if (getProc.cancelled) {
        getProc.cancelled = false
        return
      }
      if (code !== 0 && getProc.launchSeq === root.requestSeq && root.status === "loading")
        root.finish({ lines: [], plainText: "", status: "error" })
    }
  }

  // Fuzzy fallback: /api/search needs only artist and track, and returns up to
  // 20 candidates with durations, so the closest-length match can be chosen.
  function startSearch() {
    if (getProc.launchSeq !== root.requestSeq)
      return
    searchProc.command = ["curl", "-sS", "-G", "--max-time", "10",
      "-H", "User-Agent: " + root.userAgent,
      "--data-urlencode", "artist_name=" + MediaState.trackArtist,
      "--data-urlencode", "track_name=" + MediaState.trackTitle,
      "https://lrclib.net/api/search"]
    searchProc.launchSeq = root.requestSeq
    searchProc.running = true
  }

  Process {
    id: searchProc
    property int launchSeq: -1
    property bool cancelled: false
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        if (searchProc.launchSeq !== root.requestSeq)
          return
        var list = null
        try {
          list = JSON.parse(text)
        } catch (e) {
          root.finish({ lines: [], plainText: "", status: "error" })
          return
        }
        if (!Array.isArray(list) || list.length === 0) {
          root.finish({ lines: [], plainText: "", status: "notfound" })
          return
        }

        const want = MediaState.length
        var best = null
        var bestScore = -1
        for (var i = 0; i < list.length; i++) {
          const c = list[i]
          const delta = Math.abs((c.duration || 0) - want)
          if (want > 0 && delta > 5)
            continue
          // Prefer a synced candidate, then the closest duration.
          const score = (c.syncedLyrics ? 1000 : 0) + (100 - Math.min(100, delta))
          if (score > bestScore) {
            best = c
            bestScore = score
          }
        }
        if (best === null)
          root.finish({ lines: [], plainText: "", status: "notfound" })
        else
          root.finish(root.resultFrom(best))
      }
    }
    stderr: StdioCollector {}
    onExited: function (code) {
      if (searchProc.cancelled) {
        searchProc.cancelled = false
        return
      }
      if (code !== 0 && searchProc.launchSeq === root.requestSeq && root.status === "loading")
        root.finish({ lines: [], plainText: "", status: "error" })
    }
  }

  // Callers are already guarded on launchSeq, so this only has to confirm the
  // result still belongs to the track that is currently loaded.
  function finish(res) {
    if (root.inFlightKey === "" || root.inFlightKey !== MediaState.trackKey)
      return
    // Errors are not cached; a miss is, so it is not retried constantly.
    if (res.status !== "error")
      root.remember(root.inFlightKey, res)
    root.applyResult(res)
  }

  // --- LRC parsing -----------------------------------------------------------

  // Handles `[mm:ss.cc] text` and multiple stamps on one line (`[t1][t2] text`),
  // with 2- or 3-digit fractional parts.
  function parseLrc(text) {
    const out = []
    const rows = text.split("\n")
    for (var i = 0; i < rows.length; i++) {
      const row = rows[i]
      const re = /\[(\d+):(\d+)(?:[.:](\d+))?\]/g
      const times = []
      var m
      var last = 0
      while ((m = re.exec(row)) !== null) {
        const mins = parseInt(m[1], 10)
        const secs = parseInt(m[2], 10)
        var frac = 0
        if (m[3] !== undefined) {
          const digits = m[3]
          const v = parseInt(digits, 10)
          frac = digits.length === 3 ? v : (digits.length === 2 ? v * 10 : v * 100)
        }
        times.push(mins * 60000 + secs * 1000 + frac)
        last = re.lastIndex
      }
      if (times.length === 0)
        continue
      const body = row.substring(last).trim()
      for (var t = 0; t < times.length; t++)
        out.push({ ms: times[t], text: body })
    }
    out.sort(function (a, b) { return a.ms - b.ms })
    return out
  }
}
