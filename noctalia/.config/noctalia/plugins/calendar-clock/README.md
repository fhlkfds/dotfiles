# Calendar Clock

A replacement for Noctalia's built-in `Clock` bar widget. Same capsule, three mouse actions.

## Controls

| Action | Result |
|---|---|
| **Left click** | Opens a month calendar anchored to the widget — weeks start Monday, with an ISO-8601 week-number gutter. Dismiss by clicking outside or pressing <kbd>Esc</kbd>. |
| **Right click** | Cycles the label format: `3:42 PM` → `15:42` → `Fri, Aug 21` → `2026-08-21` → back to the start. |
| **Middle click** | Timezone menu — Local (America/Chicago), New York, Denver, Los Angeles, Phoenix, UTC — plus **Widget settings**. |
| **Hover** | Tooltip with the full date and time, plus the zone name when it isn't local. |

The settings entry sits in the middle-click menu rather than its usual right-click home, because
right-click is spent on the format cycle. It's also reachable from Noctalia Settings → Plugins →
Calendar Clock.

## Timezones

Selecting a zone changes **only this widget's display**. It does not touch the system timezone,
the locale, or any other widget — verify with `timedatectl` if you like.

The implementation is worth knowing about if you ever extend it. Qt 6.11's QML engine has no
`Intl`, and `Date.toLocaleString(locale, {timeZone})` silently ignores the `timeZone` option and
returns local time. So there is no in-engine way to format an IANA zone. Instead `Main.qml`
resolves the zone's UTC offset by shelling out to `TZ=<zone> date +%z`, then shifts the `Date`
before handing it to the normal local formatter. The offset is re-resolved on zone change, every
15 minutes, and on resume from suspend, so DST transitions are picked up. A hardcoded offset table
would be wrong — Phoenix and Los Angeles share an offset in summer but diverge in winter.

`Local` is stored as the sentinel `"local"` meaning "shift by nothing", so it genuinely tracks the
system clock rather than pinning a Chicago offset.

## ISO week numbers

The gutter shows ISO-8601 week numbers, which is why weeks are forced to start Monday regardless
of `Settings.data.location.firstDayOfWeek` or the locale's Sunday default.

Week numbering is derived from each week's **Thursday**: that Thursday's year is the ISO year, and
the week index is counted from the week containing January 4. This is what makes the year-boundary
cases come out right — week 1 can begin in late December, and week 52/53 can run into January.

## Settings

Noctalia Settings → Plugins → Calendar Clock:

- **Clock format** — the starting format (right-click still cycles from there).
- **Timezone** — the starting zone.
- **Clock color** — any Noctalia color key.
- **Tooltip format** — a Qt date format string.

Choices made from the widget itself persist to `settings.json` in this directory and survive a
reload.

## Files

| File | Role |
|---|---|
| `Main.qml` | Headless: timezone offset resolution, shared `displayTime`, format/zone mutators |
| `BarWidget.qml` | The capsule, the three mouse actions, tooltip, timezone menu |
| `Panel.qml` | The calendar popup |
| `Settings.qml` | The settings pane |
