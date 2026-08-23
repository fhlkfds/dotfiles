import QtQuick

// Month grid, extracted verbatim from CalendarPopup so the popup and the
// dashboard share one implementation. Display-only; today is highlighted.
// Wraps its content tightly, so callers add their own padding.
Item {
  id: root

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()

  function goToday() {
    const now = new Date()
    viewYear = now.getFullYear()
    viewMonth = now.getMonth()
  }

  function prevMonth() {
    if (viewMonth === 0) {
      viewMonth = 11
      viewYear -= 1
    } else {
      viewMonth -= 1
    }
  }

  function nextMonth() {
    if (viewMonth === 11) {
      viewMonth = 0
      viewYear += 1
    } else {
      viewMonth += 1
    }
  }

  // Standard ISO-8601 week-number algorithm (Thursday-of-the-week rule),
  // correct across year boundaries.
  function isoWeekNumber(d) {
    const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
    const dayNum = (date.getUTCDay() + 6) % 7
    date.setUTCDate(date.getUTCDate() - dayNum + 3)
    const firstThursday = new Date(Date.UTC(date.getUTCFullYear(), 0, 4))
    const fdn = (firstThursday.getUTCDay() + 6) % 7
    firstThursday.setUTCDate(firstThursday.getUTCDate() - fdn + 3)
    return 1 + Math.round((date - firstThursday) / (7 * 24 * 3600 * 1000))
  }

  property var weeks: {
    const firstOfMonth = new Date(viewYear, viewMonth, 1)
    const firstDow = (firstOfMonth.getDay() + 6) % 7 // Monday = 0
    const gridStart = new Date(viewYear, viewMonth, 1 - firstDow)
    const result = []
    for (let w = 0; w < 6; w++) {
      const days = []
      for (let d = 0; d < 7; d++) {
        days.push(new Date(gridStart.getFullYear(), gridStart.getMonth(),
                            gridStart.getDate() + w * 7 + d))
      }
      result.push({ weekNumber: isoWeekNumber(days[0]), days: days })
    }
    return result
  }

  Column {
    id: layout
    spacing: Theme.fs(6)

    Row {
      spacing: Theme.fs(10)

      Text {
        text: "‹"
        color: Theme.text
        font.pixelSize: Theme.fs(16)
        MouseArea { anchors.fill: parent; onClicked: root.prevMonth() }
      }
      Text {
        text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
        color: Theme.text
        font.bold: true
        font.pixelSize: Theme.fs(14)
      }
      Text {
        text: "›"
        color: Theme.text
        font.pixelSize: Theme.fs(16)
        MouseArea { anchors.fill: parent; onClicked: root.nextMonth() }
      }
      Item { width: 10; height: 1 }
      Text {
        text: "Today"
        color: Theme.textDim
        font.pixelSize: Theme.fs(12)
        MouseArea { anchors.fill: parent; onClicked: root.goToday() }
      }
    }

    Row {
      spacing: Theme.fs(4)
      Text { width: 24; text: "" }
      Repeater {
        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        Text {
          width: Theme.fs(26)
          horizontalAlignment: Text.AlignHCenter
          text: modelData
          color: Theme.textDim
          font.pixelSize: Theme.fs(11)
        }
      }
    }

    Repeater {
      model: root.weeks
      Row {
        spacing: Theme.fs(4)
        Text {
          width: Theme.fs(24)
          horizontalAlignment: Text.AlignHCenter
          text: modelData.weekNumber
          color: Theme.textMuted
          font.pixelSize: Theme.fs(11)
        }
        Repeater {
          model: modelData.days
          Rectangle {
            width: Theme.fs(26)
            height: Theme.fs(26)
            radius: Theme.fs(4)
            property bool inMonth: modelData.getMonth() === root.viewMonth
            property bool isToday: {
              const t = new Date()
              return modelData.getFullYear() === t.getFullYear()
                  && modelData.getMonth() === t.getMonth()
                  && modelData.getDate() === t.getDate()
            }
            color: isToday ? Theme.accent : "transparent"

            Text {
              anchors.centerIn: parent
              text: modelData.getDate()
              font.pixelSize: Theme.fs(12)
              color: isToday ? Theme.bgDeep : (inMonth ? Theme.text : Theme.textFaint)
            }
          }
        }
      }
    }
  }
}
