pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Weather from Open-Meteo (api.open-meteo.com).
//
// Chosen because it needs no API key and no account, and returns current
// conditions, hourly precipitation probability and a daily forecast in one
// request. Conditions arrive as WMO codes, mapped to glyph + label below.
Singleton {
  id: root

  // Location: a city picked on the dashboard weather tab wins, and one saved
  // there with "Set as default" wins on every boot. Otherwise the night-light
  // state file: location-detect.service fills it from the IP address at each
  // login, and the night-light panel (Super+Shift+N) can set it by hand.
  // weather.json next to this file is the default, and Chicago the last resort.
  property real latitude: 41.8781
  property real longitude: -87.6298
  property string timezone: "America/Chicago"
  property bool savedLocation: false
  property bool userChoice: false
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
                                      || Quickshell.env("HOME") + "/.local/state"
  // locationKey of the saved default; "" until one is loaded or saved.
  property string defaultKey: ""
  property bool defaultLoaded: false
  property bool savingDefault: false
  property string pendingDefaultKey: ""
  property string defaultError: ""
  readonly property bool isDefault: defaultKey !== "" && defaultKey === locationKey
  // The night-light panel saves a place name with its location; weather.json
  // has none, so fall back to the city in the timezone id.
  property string place: ""
  readonly property string locationName: place !== ""
    ? place.split(",")[0]
    : timezone.substring(timezone.lastIndexOf("/") + 1).replace(/_/g, " ")

  function validLocation(c) {
    return !!c && typeof c.latitude === "number" && typeof c.longitude === "number"
      && isFinite(c.latitude) && isFinite(c.longitude)
      && Math.abs(c.latitude) <= 90 && Math.abs(c.longitude) <= 180
  }

  function applyLocation(c) {
    if (!root.validLocation(c))
      return false
    root.latitude = c.latitude
    root.longitude = c.longitude
    if (typeof c.timezone === "string" && c.timezone !== "") root.timezone = c.timezone
    root.current = null
    root.hourly = []
    root.daily = []
    root.lastFetchMs = 0
    root.refresh()
    return true
  }

  FileView {
    path: Qt.resolvedUrl("weather.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (root.savedLocation || root.userChoice || root.savingDefault)
        return
      try {
        root.applyLocation(JSON.parse(text()))
      } catch (e) {}
    }
  }

  FileView {
    path: root.stateHome + "/night-light/schedule.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (root.userChoice || root.savingDefault)
        return
      try {
        const loc = JSON.parse(text()).location
        const same = loc && loc.latitude === root.latitude && loc.longitude === root.longitude
          && (!loc.timezone || loc.timezone === root.timezone)
        // The panel rewrites this file on every click; only a new location
        // is worth a weather request.
        if (same)
          root.savedLocation = true
        else if (root.applyLocation(loc))
          root.savedLocation = true
        // A new location without a name must not keep the old one's.
        if (root.savedLocation)
          root.place = typeof loc.place === "string" ? loc.place : ""
      } catch (e) {}
    }
  }

  FileView {
    path: root.stateHome + "/hyprland-desktop/weather/location.json"
    printErrors: false
    onLoaded: root.loadDefault(text())
    onLoadFailed: root.defaultLoaded = true
  }

  FileView {
    id: defaultWriter
    preload: false
    printErrors: false
    onSaved: root.finishDefaultSave(true)
    onSaveFailed: root.finishDefaultSave(false)
  }

  function loadDefault(text) {
    // Read once; writes must not replace a newer selection or refetch weather.
    if (root.defaultLoaded || root.savingDefault)
      return
    root.defaultLoaded = true
    try {
      const c = JSON.parse(text)
      if (!root.validLocation(c))
        return
      const tz = typeof c.timezone === "string" && c.timezone !== "" ? c.timezone : "auto"
      root.defaultKey = c.latitude + "," + c.longitude + "," + tz
      if (!root.userChoice)
        root.selectCity(c)
    } catch (e) {}
  }

  function selectCity(c) {
    if (!root.validLocation(c))
      return false
    // Missing geocoder timezones must not inherit the previous city's zone.
    const tz = typeof c.timezone === "string" && c.timezone !== "" ? c.timezone : "auto"
    root.applyLocation({latitude: c.latitude, longitude: c.longitude, timezone: tz})
    root.userChoice = true
    root.place = typeof c.place === "string" ? c.place : ""
    root.defaultError = ""
    return true
  }

  function saveDefault() {
    if (root.savingDefault)
      return
    root.savingDefault = true
    root.defaultError = ""
    root.pendingDefaultKey = root.locationKey
    // FileView skips identical cached text even after a failed write. Reset
    // this write-only view so every retry starts an actual atomic disk write.
    defaultWriter.path = ""
    defaultWriter.path = root.stateHome + "/hyprland-desktop/weather/location.json"
    defaultWriter.setText(JSON.stringify({latitude: root.latitude, longitude: root.longitude,
      timezone: root.timezone, place: root.place}, null, 2) + "\n")
  }

  function finishDefaultSave(success) {
    if (!root.savingDefault)
      return
    if (success) {
      root.defaultKey = root.pendingDefaultKey
      root.userChoice = true
      root.defaultLoaded = true
    } else {
      root.defaultError = "Could not save default; check the weather state directory and retry."
    }
    root.pendingDefaultKey = ""
    root.savingDefault = false
  }

  // --- city search -----------------------------------------------------------

  // Open-Meteo's geocoder, same service as the forecast. Its matching is
  // fuzzy, so only places whose name starts with the typed text are kept.
  property var cityResults: []
  property string cityQuery: ""
  property string searchedQuery: ""
  property string resultsQuery: ""
  property string citySearchStatus: "idle"

  function updateCityQuery(query) {
    const q = query.trim()
    if (root.cityQuery === q)
      return
    root.cityQuery = q
    root.cityResults = []
    root.resultsQuery = ""
    root.citySearchStatus = "idle"
  }

  function canPickCity(query) {
    return query.trim().length >= 2 && root.resultsQuery === query.trim()
      && root.cityResults.length > 0
  }

  function searchCities(query) {
    root.updateCityQuery(query)
    if (root.cityQuery.length < 2) {
      root.cityResults = []
      return
    }
    if (searchProc.running)
      return
    root.citySearchStatus = "loading"
    root.searchedQuery = root.cityQuery
    searchProc.command = ["curl", "-fsS", "--max-time", "10", "-G",
      "--data-urlencode", "name=" + root.searchedQuery,
      "--data-urlencode", "count=50",
      "--data-urlencode", "language=en",
      "https://geocoding-api.open-meteo.com/v1/search"]
    searchProc.running = true
  }

  function parseCities(text, query) {
    var d = null
    try {
      d = JSON.parse(text)
    } catch (e) {
      return []
    }
    const q = query.toLowerCase()
    return ((d && Array.isArray(d.results)) ? d.results : [])
      .filter(r => r && typeof r.name === "string" && r.name.toLowerCase().startsWith(q)
              // PPL* are populated places; drops peaks, parks and countries.
              && String(r.feature_code).startsWith("PPL")
              && root.validLocation(r))
      .sort((a, b) => (b.population || 0) - (a.population || 0))
      .slice(0, 8)
      .map(r => {
        const detail = [r.admin1, r.country_code].filter(s => typeof s === "string" && s !== "").join(", ")
        return {name: r.name, detail: detail, latitude: r.latitude, longitude: r.longitude,
                timezone: typeof r.timezone === "string" && r.timezone !== "" ? r.timezone : "auto",
                place: detail !== "" ? r.name + ", " + detail : r.name}
      })
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOutput }
    onExited: code => root.finishCitySearch(code, searchOutput.text)
  }

  function finishCitySearch(code, text) {
    if (root.searchedQuery !== root.cityQuery) {
      Qt.callLater(() => root.searchCities(root.cityQuery))
      return
    }
    root.cityResults = []
    root.resultsQuery = ""
    try {
      const d = JSON.parse(text)
      if (code !== 0 || !d || d.error)
        throw new Error("City search failed")
      root.cityResults = root.parseCities(text, root.searchedQuery)
      root.resultsQuery = root.searchedQuery
      root.citySearchStatus = "ok"
    } catch (e) {
      root.citySearchStatus = "error"
    }
  }

  // idle | loading | ok | error
  property string status: "idle"
  property string errorText: ""
  // Kept so a failed refresh shows the last good data rather than blanking.
  property double lastFetchMs: 0
  readonly property int refreshIntervalMs: 15 * 60 * 1000

  property var current: null      // { temp, feels, humidity, code, wind, isDay, precip, uv }
  property var hourly: []         // [{ time, temp, precipProb, code }]
  property var daily: []          // [{ date, code, tMax, tMin, precipMax, sunrise, sunset, uvMax }]

  readonly property bool hasData: current !== null

  // Forecast timestamps belong to the requested location, not the host.
  // A minute clock advances cached strips across hour/day boundaries.
  property int utcOffsetSeconds: 0
  SystemClock { id: forecastClock; precision: SystemClock.Minutes }
  function hourAt(ms) {
    return new Date(ms + root.utcOffsetSeconds * 1000).toISOString().slice(0, 13) + ":00"
  }
  readonly property string forecastHour: hourAt(forecastClock.date.getTime())
  readonly property var upcomingDays: daily.filter(d => d.date >= forecastHour.slice(0, 10))
  readonly property string locationKey: latitude + "," + longitude + "," + timezone
  property string fetchLocationKey: ""

  Component.onCompleted: root.maybeRefresh()

  // --- fetching --------------------------------------------------------------

  // Only actually hits the network if the cached result has expired.
  function maybeRefresh() {
    const age = Date.now() - root.lastFetchMs
    if (root.hasData && age < root.refreshIntervalMs)
      return
    root.refresh()
  }

  function refresh() {
    if (fetchProc.running)
      return
    root.status = "loading"
    root.fetchLocationKey = root.locationKey
    fetchProc.command = ["curl", "-sS", "--max-time", "15", "-G",
      "--data-urlencode", "latitude=" + root.latitude,
      "--data-urlencode", "longitude=" + root.longitude,
      "--data-urlencode", "current=temperature_2m,apparent_temperature,"
        + "relative_humidity_2m,weather_code,wind_speed_10m,is_day,precipitation,uv_index",
      "--data-urlencode", "hourly=temperature_2m,precipitation_probability,weather_code",
      "--data-urlencode", "daily=weather_code,temperature_2m_max,temperature_2m_min,"
        + "precipitation_probability_max,sunrise,sunset,uv_index_max",
      "--data-urlencode", "temperature_unit=fahrenheit",
      "--data-urlencode", "wind_speed_unit=mph",
      "--data-urlencode", "timezone=" + root.timezone,
      "--data-urlencode", "forecast_days=10",
      "https://api.open-meteo.com/v1/forecast"]
    fetchProc.running = true
  }

  // The cache check keeps this to one request per 15 minutes.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.maybeRefresh()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      onStreamFinished: root.acceptForecast(text)
    }
    stderr: StdioCollector { id: fetchErr }
    onExited: function (code) {
      if (root.fetchLocationKey !== root.locationKey) {
        Qt.callLater(root.refresh)
        return
      }
      if (code !== 0 && root.status === "loading")
        root.fail(fetchErr.text.trim() || "Could not reach Open-Meteo")
    }
  }

  function acceptForecast(text) {
    if (root.fetchLocationKey !== root.locationKey)
      return
    var d = null
    try {
      d = JSON.parse(text)
    } catch (e) {
      root.fail("Malformed weather response")
      return
    }
    if (!d || d.error || !d.current) {
      root.fail(d && d.reason ? d.reason : "Weather unavailable")
      return
    }
    const c = d.current
    const required = [c.temperature_2m, c.apparent_temperature, c.relative_humidity_2m,
                      c.weather_code, c.wind_speed_10m, c.is_day]
    if (!required.every(v => typeof v === "number" && isFinite(v))) {
      root.fail("Incomplete current weather")
      return
    }
    const h = d.hourly
    const day = d.daily
    if ((h && ![h.time, h.temperature_2m, h.precipitation_probability, h.weather_code].every(Array.isArray))
        || (day && ![day.time, day.weather_code, day.temperature_2m_max, day.temperature_2m_min,
                     day.precipitation_probability_max, day.sunrise, day.sunset].every(Array.isArray))) {
      root.fail("Incomplete weather forecast")
      return
    }

    const hs = []
    if (h) {
      for (var i = 0; i < h.time.length; i++) {
        if (typeof h.time[i] !== "string" || typeof h.temperature_2m[i] !== "number"
            || !isFinite(h.temperature_2m[i])) continue
        hs.push({time: h.time[i], temp: h.temperature_2m[i],
                 precipProb: h.precipitation_probability[i], code: h.weather_code[i]})
      }
    }
    const ds = []
    if (day) {
      for (var j = 0; j < day.time.length; j++) {
        if (typeof day.time[j] !== "string" || typeof day.temperature_2m_min[j] !== "number"
            || typeof day.temperature_2m_max[j] !== "number"
            || !isFinite(day.temperature_2m_min[j]) || !isFinite(day.temperature_2m_max[j])) continue
        ds.push({date: day.time[j], code: day.weather_code[j],
                 tMax: day.temperature_2m_max[j], tMin: day.temperature_2m_min[j],
                 precipMax: day.precipitation_probability_max[j],
                 sunrise: typeof day.sunrise[j] === "string" ? day.sunrise[j] : "",
                 sunset: typeof day.sunset[j] === "string" ? day.sunset[j] : "",
                 uvMax: day.uv_index_max ? day.uv_index_max[j] : null})
      }
    }

    // Commit a complete response together; malformed responses keep the cache.
    root.utcOffsetSeconds = Number(d.utc_offset_seconds) || 0
    root.current = {temp: c.temperature_2m, feels: c.apparent_temperature,
                    humidity: c.relative_humidity_2m, code: c.weather_code,
                    wind: c.wind_speed_10m, isDay: c.is_day === 1,
                    precip: c.precipitation, uv: c.uv_index}
    root.hourly = hs
    root.daily = ds
    root.lastFetchMs = Date.now()
    root.status = "ok"
    root.errorText = ""
  }

  function fail(msg) {
    root.errorText = msg
    // Keep any previously fetched data on screen; only the badge changes.
    root.status = "error"
  }

  // --- upcoming rain ---------------------------------------------------------

  readonly property int rainThreshold: 40

  // First upcoming hour (within ~12h) whose precipitation probability crosses
  // the threshold. null when no rain is expected.
  readonly property var rainSoon: {
    if (root.hourly.length === 0)
      return null
    const nowIso = root.forecastHour
    var start = -1
    for (var i = 0; i < root.hourly.length; i++) {
      if (root.hourly[i].time >= nowIso) { start = i; break }
    }
    if (start < 0)
      return null
    const end = Math.min(root.hourly.length, start + 12)
    for (var j = start; j < end; j++) {
      if (root.hourly[j].precipProb >= root.rainThreshold) {
        return {
          time: root.hourly[j].time,
          prob: root.hourly[j].precipProb,
          hoursAway: j - start
        }
      }
    }
    return null
  }

  // Hourly entries from the current hour onward, for the forecast strip.
  readonly property var upcomingHours: {
    if (root.hourly.length === 0)
      return []
    const nowIso = root.forecastHour
    for (var i = 0; i < root.hourly.length; i++) {
      if (root.hourly[i].time >= nowIso)
        return root.hourly.slice(i, i + 24)
    }
    return []
  }

  // --- WMO code mapping ------------------------------------------------------

  // Codepoints verified against the installed JetBrainsMono Nerd Font cmap.
  function codeGlyph(code, isDay) {
    switch (code) {
    case 0:  return isDay ? String.fromCodePoint(0xf0599)  // md-weather_sunny
                          : String.fromCodePoint(0xf0594)  // md-weather_night
    case 1:
    case 2:  return isDay ? String.fromCodePoint(0xf0595)  // md-weather_partly_cloudy
                          : String.fromCodePoint(0xf0f31)  // md-weather_night_partly_cloudy
    case 3:  return String.fromCodePoint(0xf0590)          // md-weather_cloudy
    case 45:
    case 48: return String.fromCodePoint(0xf0591)          // md-weather_fog
    case 51: case 53: case 55:
    case 56: case 57:
             return String.fromCodePoint(0xf0f33)          // md-weather_partly_rainy
    case 61: case 63:
    case 66: case 67:
             return String.fromCodePoint(0xf0597)          // md-weather_rainy
    case 65: return String.fromCodePoint(0xf0596)          // md-weather_pouring
    case 71: case 73: case 75: case 77:
             return String.fromCodePoint(0xf0598)          // md-weather_snowy
    case 80: case 81:
             return String.fromCodePoint(0xf0597)          // md-weather_rainy
    case 82: return String.fromCodePoint(0xf0596)          // md-weather_pouring
    case 85: case 86:
             return String.fromCodePoint(0xf0598)          // md-weather_snowy
    case 95: return String.fromCodePoint(0xf0593)          // md-weather_lightning
    case 96: case 99:
             return String.fromCodePoint(0xf067e)          // md-weather_lightning_rainy
    default: return String.fromCodePoint(0xf0590)          // md-weather_cloudy
    }
  }

  function codeLabel(code) {
    switch (code) {
    case 0:  return "Clear"
    case 1:  return "Mainly clear"
    case 2:  return "Partly cloudy"
    case 3:  return "Overcast"
    case 45: return "Fog"
    case 48: return "Freezing fog"
    case 51: return "Light drizzle"
    case 53: return "Drizzle"
    case 55: return "Heavy drizzle"
    case 56: case 57: return "Freezing drizzle"
    case 61: return "Light rain"
    case 63: return "Rain"
    case 65: return "Heavy rain"
    case 66: case 67: return "Freezing rain"
    case 71: return "Light snow"
    case 73: return "Snow"
    case 75: return "Heavy snow"
    case 77: return "Snow grains"
    case 80: return "Light showers"
    case 81: return "Showers"
    case 82: return "Violent showers"
    case 85: return "Snow showers"
    case 86: return "Heavy snow showers"
    case 95: return "Thunderstorm"
    case 96: case 99: return "Thunderstorm with hail"
    default: return "Unknown"
    }
  }

  // Day/night for an hourly timestamp, taken from that date's sunrise/sunset so
  // the forecast strip does not show a sun at 2 AM. ISO strings of identical
  // format compare correctly as strings.
  function isDayAt(iso) {
    const date = iso.substring(0, 10)
    for (var i = 0; i < root.daily.length; i++) {
      if (root.daily[i].date === date)
        return iso >= root.daily[i].sunrise && iso < root.daily[i].sunset
    }
    const h = parseInt(iso.substring(11, 13), 10)
    return h >= 6 && h < 20
  }

  // WHO UV index bands.
  function uvLabel(uv) {
    if (uv === null || uv === undefined || !isFinite(uv)) return "--"
    if (uv < 3) return "Low"
    if (uv < 6) return "Moderate"
    if (uv < 8) return "High"
    if (uv < 11) return "Very high"
    return "Extreme"
  }

  function fmtPercent(v) {
    return typeof v === "number" && isFinite(v) ? Math.round(v) + "%" : "--"
  }

  function fmtTemp(t) {
    return (t !== null && t !== undefined && isFinite(t) ? Math.round(t) : "--") + "°F"
  }

  function fmtHour(iso) {
    // "2026-08-22T18:00" -> "6 PM"
    const d = Date.fromLocaleString(Qt.locale(), iso, "yyyy-MM-ddThh:mm")
    return isNaN(d.getTime()) ? iso.substring(11, 16)
                              : Qt.formatDateTime(d, "h AP")
  }

  function fmtDay(iso) {
    const d = Date.fromLocaleString(Qt.locale(), iso, "yyyy-MM-dd")
    return isNaN(d.getTime()) ? iso : Qt.formatDateTime(d, "ddd")
  }

  function fmtClock(iso) {
    if (!iso) return "--"
    const d = Date.fromLocaleString(Qt.locale(), iso, "yyyy-MM-ddThh:mm")
    return isNaN(d.getTime()) ? iso.substring(11, 16)
                              : Qt.formatDateTime(d, "h:mm AP")
  }
}
