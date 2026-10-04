import QtQuick
import QtQuick.Window

Window {
  id: win
  property string tab: "overview"
  property real scaleFactor: 1.0
  property bool fixtureShown: true
  property int viewportWidth: 0
  property int viewportHeight: 0
  property QtObject fixtureView: view
  property string themeSlug: Theme.themeSlug
  property string selectedTab: DashboardState.activeTab
  function reloadPalette() { Theme.reloadPalette() }
  function setScale(s) { Theme.fontScale = s }
  function missingData() {
    SysState.gpuReported = false; SysState.gpuTempReported = false; SysState.cpuTempReported = false
    SysState.gpuVramTotalBytes = 0; SysState.gpuPowerW = -1
    WeatherState.current = null; WeatherState.hourly = []; WeatherState.daily = []; WeatherState.status = "error"
    MediaState.hasTrack = false; LyricsState.status = "idle"
  }
  onTabChanged: DashboardState.activeTab = tab
  width: (viewportWidth || view.implicitWidth) + 48
  height: (viewportHeight || view.implicitHeight) + 48
  visible: true
  color: "#0d0e14"

  DashboardView { id: view; x: 24; y: 24; width: win.viewportWidth || implicitWidth; height: win.viewportHeight || implicitHeight; shown: win.fixtureShown }

  Component.onCompleted: {
    Theme.fontScale = scaleFactor
    WeatherState.savedLocation = true; WeatherState.timezone = "America/Chicago"; WeatherState.utcOffsetSeconds = -18000; WeatherState.place = "Chicago"
    // Weather fixture, in the shape WeatherState's parser produces.
    const hourly = []
    const temps = [66,64,64,64,63,61,63,68,73,79,81,81, 80,77,72,70,68,66,65,64,64,63,65,70]
    for (let i = 0; i < 48; i++) {
      const d = new Date(2026, 9, 3, 13 + i, 0)
      hourly.push({ time: Qt.formatDateTime(d, "yyyy-MM-ddThh:00"), temp: temps[Math.floor(i/2) % 24] + (i % 2),
                    precipProb: [0,0,5,10,20,35,45,25,10,0,0,5][Math.floor(i/2) % 12], code: [0,0,1,2,0,2,3,61,2,1,3,3][Math.floor(i/2) % 12] })
    }
    WeatherState.hourly = hourly
    WeatherState.daily = [
      { date: "2026-10-01", code: 3,  tMax: 74, tMin: 62, precipMax: 0,  sunrise: "2026-10-01T06:55", sunset: "2026-10-01T18:36", uvMax: 6 },
      { date: "2026-10-02", code: 3,  tMax: 82, tMin: 61, precipMax: 0,  sunrise: "2026-10-02T06:56", sunset: "2026-10-02T18:34", uvMax: 6 },
      { date: "2026-10-03", code: 2,  tMax: 82, tMin: 68, precipMax: 8,  sunrise: "2026-10-03T06:57", sunset: "2026-10-03T18:32", uvMax: 5 },
      { date: "2026-10-04", code: 61, tMax: 79, tMin: 70, precipMax: 45, sunrise: "2026-10-04T06:58", sunset: "2026-10-04T18:31", uvMax: 5 },
      { date: "2026-10-05", code: 61, tMax: 75, tMin: 68, precipMax: 15, sunrise: "2026-10-05T06:59", sunset: "2026-10-05T18:29", uvMax: 4 },
      { date: "2026-10-06", code: 63, tMax: 72, tMin: 68, precipMax: 28, sunrise: "2026-10-06T07:00", sunset: "2026-10-06T18:27", uvMax: 3 },
      { date: "2026-10-07", code: 2,  tMax: 72, tMin: 64, precipMax: 11, sunrise: "2026-10-07T07:01", sunset: "2026-10-07T18:26", uvMax: 5 } ]
    WeatherState.daily = WeatherState.daily.map((d, i) => {
      const date = Qt.formatDate(new Date(2026, 9, 3 + i), "yyyy-MM-dd")
      return Object.assign({}, d, {date, sunrise: date + d.sunrise.slice(10), sunset: date + d.sunset.slice(10)})
    })
    WeatherState.current = { temp: 66.4, feels: 63, humidity: 62, code: 0, wind: 9, isDay: false, precip: 0, uv: 0 }
    WeatherState.lastFetchMs = new Date(2026, 9, 3, 18, 30).getTime()
    WeatherState.status = "ok"

    // System fixture.
    const wave = n => Array.from({ length: 60 }, (_, i) => 0.14 + 0.05 * Math.sin(i / 3) + 0.03 * Math.sin(i * 1.7))
    SysState.hostname = "archlinux"; SysState.kernel = "7.2.8-arch1-1"
    SysState.cpuModel = "11th Gen Intel(R) Core(TM) i7-11800H @ 2.30GHz"
    SysState.gpuModel = "GeForce GTX 1650 Mobile / Max-Q"
    SysState.cpuPercent = 18; SysState.cpuSeeded = true; SysState.cpuTempC = 52; SysState.cpuTempPath = ""; SysState.cpuTempReported = true
    SysState.cpuFreqGhz = 1.85; SysState.loadAvg = 2.75
    SysState.coreUsage = [0.3,0.1,0.2,0.15,0.4,0.12,0.08,0.22,0.1,0.35,0.05,0.18,0.09,0.27,0.14,0.11]
    SysState.cpuHistory = wave()
    SysState.memTotalBytes = 23.2 * 1073741824; SysState.memUsedBytes = 14.1 * 1073741824
    SysState.swapTotalBytes = 4 * 1073741824; SysState.swapUsedBytes = 0
    SysState.diskTotalBytes = 930.5 * 1073741824; SysState.diskUsedBytes = 103.2 * 1073741824
    SysState.nvidiaDevPath = ""; SysState.nvidiaSmi = true
    SysState.gpuReported = true; SysState.gpuPercent = 37; SysState.gpuTempC = 51; SysState.gpuTempReported = true
    SysState.gpuVramUsedBytes = 1.4 * 1073741824; SysState.gpuVramTotalBytes = 4 * 1073741824; SysState.gpuPowerW = 22
    SysState.gpuHistory = Array.from({ length: 60 }, (_, i) => i > 50 ? 0.37 : 0.02)
    SysState.netIface = "wlan0"; SysState.rxRate = 132; SysState.txRate = 172
    SysState.rxTotal = 2.1 * 1048576; SysState.txTotal = 4.3 * 1048576
    SysState.rxHistory = Array.from({ length: 60 }, (_, i) => [5, 9, 14, 22].includes(i % 25) ? 400 + (i % 7) * 120 : 30)
    SysState.txHistory = Array.from({ length: 60 }, (_, i) => i % 11 === 4 ? 900 : 60)
    SysState.uptimeSeconds = 6540
  }
}
