.pragma library

// US federal holidays, computed rather than fetched, so the dashboard calendar
// needs no network and never goes stale. Observed-day shifts (a Saturday
// holiday taken on the Friday) are deliberately not modelled: the calendar
// marks the holiday itself.

// nth (1-based) weekday of a month; n = -1 is the last one.
function nthWeekday(year, month, weekday, n) {
  if (n < 0) {
    const last = new Date(year, month + 1, 0)
    return last.getDate() - (last.getDay() - weekday + 7) % 7
  }
  const first = new Date(year, month, 1).getDay()
  return 1 + (weekday - first + 7) % 7 + (n - 1) * 7
}

function forYear(year) {
  return [
    { month: 0,  day: 1,                              name: "New Year's Day" },
    { month: 0,  day: nthWeekday(year, 0, 1, 3),      name: "Martin Luther King Jr. Day" },
    { month: 1,  day: nthWeekday(year, 1, 1, 3),      name: "Presidents' Day" },
    { month: 4,  day: nthWeekday(year, 4, 1, -1),     name: "Memorial Day" },
    { month: 5,  day: 19,                             name: "Juneteenth" },
    { month: 6,  day: 4,                              name: "Independence Day" },
    { month: 8,  day: nthWeekday(year, 8, 1, 1),      name: "Labor Day" },
    { month: 9,  day: nthWeekday(year, 9, 1, 2),      name: "Columbus Day" },
    { month: 10, day: 11,                             name: "Veterans Day" },
    { month: 10, day: nthWeekday(year, 10, 4, 4),     name: "Thanksgiving" },
    { month: 11, day: 25,                             name: "Christmas Day" }
  ]
}

// Holiday name for a date, or "".
function nameOn(date) {
  const list = forYear(date.getFullYear())
  for (var i = 0; i < list.length; i++)
    if (list[i].month === date.getMonth() && list[i].day === date.getDate())
      return list[i].name
  return ""
}

// The first holiday on or after `from`: { name, date, days }.
function next(from) {
  const today = new Date(from.getFullYear(), from.getMonth(), from.getDate())
  for (var y = today.getFullYear(); y <= today.getFullYear() + 1; y++) {
    const list = forYear(y)
    for (var i = 0; i < list.length; i++) {
      const d = new Date(y, list[i].month, list[i].day)
      if (d >= today)
        return { name: list[i].name, date: d, days: Math.round((d - today) / 86400000) }
    }
  }
  return null
}
