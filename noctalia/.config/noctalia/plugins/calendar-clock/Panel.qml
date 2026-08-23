import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Left-click calendar popup. Hosted by the shell's SmartPanel, which supplies
// anchoring to the bar widget plus outside-click and Esc dismissal, so none of
// that is implemented here.
Item {
  id: root

  property var pluginApi: null

  // SmartPanel contract
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true
  property real contentPreferredWidth: 330 * Style.uiScaleRatio
  property real contentPreferredHeight: calendarContent.implicitHeight + Style.marginL * 2

  anchors.fill: parent

  readonly property var mainInstance: pluginApi?.mainInstance ?? null

  // "Today" follows the widget's selected timezone, so picking UTC late in the
  // evening correctly highlights tomorrow.
  readonly property var today: mainInstance?.displayTime ?? new Date()

  // Weeks start Monday, deliberately ignoring Settings.data.location.firstDayOfWeek
  // and the locale's Sunday default: ISO-8601 week numbering requires it.
  readonly property int firstDayOfWeek: 1

  property int viewYear: 0
  property int viewMonth: 0

  readonly property bool viewingCurrentMonth: root.viewYear === root.today.getFullYear() && root.viewMonth === root.today.getMonth()

  function goToToday() {
    root.viewYear = root.today.getFullYear();
    root.viewMonth = root.today.getMonth();
  }

  function stepMonth(delta) {
    var m = root.viewMonth + delta;
    var y = root.viewYear;
    while (m < 0) {
      m += 12;
      y -= 1;
    }
    while (m > 11) {
      m -= 12;
      y += 1;
    }
    root.viewMonth = m;
    root.viewYear = y;
  }

  // ISO-8601 week number. The week's Thursday determines both the ISO year and
  // the week index, which is what makes late-December and early-January weeks
  // fall out correctly (week 1 may start in December; week 52/53 may end in January).
  function isoWeekNumber(year, month, day) {
    // Built at local midnight so a timezone-shifted time-of-day can't skew the rounding.
    var target = new Date(year, month, day);
    var dayNr = (target.getDay() + 6) % 7; // Mon = 0 ... Sun = 6
    target.setDate(target.getDate() - dayNr + 3); // the Thursday of this week
    var isoYear = target.getFullYear();

    // Jan 4 is always in ISO week 1; step to that week's Thursday.
    var firstThursday = new Date(isoYear, 0, 4);
    var fDayNr = (firstThursday.getDay() + 6) % 7;
    firstThursday.setDate(firstThursday.getDate() - fDayNr + 3);

    return 1 + Math.round((target.getTime() - firstThursday.getTime()) / (7 * 24 * 60 * 60 * 1000));
  }

  Component.onCompleted: root.goToToday()

  onVisibleChanged: {
    if (visible)
      root.goToToday();
  }

  Item {
    id: panelContainer

    anchors.fill: parent

    ColumnLayout {
      id: calendarContent

      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginS

      // ── Navigation ────────────────────────────────────────────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NText {
          text: I18n.locale.monthName(root.viewMonth, Locale.LongFormat).toUpperCase() + " " + root.viewYear
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        NDivider {
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "chevron-left"
          tooltipText: root.pluginApi?.tr("calendar.previous-month")
          onClicked: root.stepMonth(-1)
        }

        NIconButton {
          icon: "calendar"
          enabled: !root.viewingCurrentMonth
          tooltipText: root.pluginApi?.tr("calendar.today")
          onClicked: root.goToToday()
        }

        NIconButton {
          icon: "chevron-right"
          tooltipText: root.pluginApi?.tr("calendar.next-month")
          onClicked: root.stepMonth(1)
        }
      }

      // ── Day-name header ───────────────────────────────────────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: 0

        // Gutter above the week numbers.
        Item {
          Layout.preferredWidth: Style.baseWidgetSize * 0.7
          Layout.preferredHeight: Style.baseWidgetSize * 0.6

          NText {
            anchors.centerIn: parent
            text: root.pluginApi?.tr("calendar.week-abbrev") ?? "W"
            color: Qt.alpha(Color.mPrimary, 0.7)
            pointSize: Style.fontSizeXXS
            font.weight: Style.fontWeightBold
          }
        }

        GridLayout {
          Layout.fillWidth: true
          columns: 7
          columnSpacing: Style.marginXXS

          Repeater {
            model: 7

            Item {
              id: dayNameCell

              required property int index

              Layout.fillWidth: true
              Layout.preferredHeight: Style.baseWidgetSize * 0.6

              NText {
                anchors.centerIn: parent
                // QML Locale.dayName is 0 = Sunday, so Monday-start maps index 0 -> 1.
                text: {
                  var dayIndex = (root.firstDayOfWeek + dayNameCell.index) % 7;
                  return I18n.locale.dayName(dayIndex, Locale.ShortFormat).substring(0, 2).toUpperCase();
                }
                color: Color.mPrimary
                pointSize: Style.fontSizeS
                font.weight: Style.fontWeightBold
              }
            }
          }
        }
      }

      // ── Week numbers + day grid ───────────────────────────────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: 0

        ColumnLayout {
          Layout.preferredWidth: Style.baseWidgetSize * 0.7
          Layout.alignment: Qt.AlignTop
          spacing: Style.marginXXS

          Repeater {
            // One entry per grid row, derived from that row's Monday.
            model: {
              var days = grid.daysModel;
              var weeks = [];
              for (var i = 0; i < days.length; i += 7) {
                var d = days[i];
                weeks.push(root.isoWeekNumber(d.year, d.month, d.day));
              }
              return weeks;
            }

            Item {
              id: weekCell

              required property int modelData

              Layout.preferredWidth: Style.baseWidgetSize * 0.7
              Layout.preferredHeight: Style.baseWidgetSize * 0.9

              NText {
                anchors.centerIn: parent
                text: weekCell.modelData
                color: Qt.alpha(Color.mPrimary, 0.7)
                pointSize: Style.fontSizeXXS
                features: ({
                    "tnum": 1
                  })
              }
            }
          }
        }

        GridLayout {
          id: grid

          Layout.fillWidth: true
          columns: 7
          columnSpacing: Style.marginXXS
          rowSpacing: Style.marginXXS

          // Flat array of {day, month, year, today, currentMonth} including the
          // leading/trailing spill days that pad the first and last weeks.
          property var daysModel: {
            const year = root.viewYear;
            const month = root.viewMonth;
            const fdow = root.firstDayOfWeek;

            const firstOfMonth = new Date(year, month, 1);
            const lastOfMonth = new Date(year, month + 1, 0);
            const daysInMonth = lastOfMonth.getDate();

            const daysBefore = (firstOfMonth.getDay() - fdow + 7) % 7;
            const daysAfter = (fdow - lastOfMonth.getDay() - 1 + 7) % 7;

            const days = [];
            const t = root.today;
            const prevMonthDays = new Date(year, month, 0).getDate();

            // Normalise the neighbouring months explicitly. Carrying month-1 together
            // with year-1 would double-decrement (new Date(2013, -1, d) is Dec 2012),
            // which matters here because these fields feed the ISO week calculation.
            const prevMonth = month === 0 ? 11 : month - 1;
            const prevYear = month === 0 ? year - 1 : year;
            const nextMonth = month === 11 ? 0 : month + 1;
            const nextYear = month === 11 ? year + 1 : year;

            for (var i = daysBefore - 1; i >= 0; i--) {
              days.push({
                "day": prevMonthDays - i,
                "month": prevMonth,
                "year": prevYear,
                "today": false,
                "currentMonth": false
              });
            }

            for (var d = 1; d <= daysInMonth; d++) {
              const isToday = t.getFullYear() === year && t.getMonth() === month && t.getDate() === d;
              days.push({
                "day": d,
                "month": month,
                "year": year,
                "today": isToday,
                "currentMonth": true
              });
            }

            for (var j = 1; j <= daysAfter; j++) {
              days.push({
                "day": j,
                "month": nextMonth,
                "year": nextYear,
                "today": false,
                "currentMonth": false
              });
            }

            return days;
          }

          Repeater {
            model: grid.daysModel

            Item {
              id: dayCell

              required property var modelData

              Layout.fillWidth: true
              Layout.preferredHeight: Style.baseWidgetSize * 0.9

              Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                radius: Style.radiusM
                color: dayCell.modelData.today ? Color.mSecondary : "transparent"

                NText {
                  anchors.centerIn: parent
                  text: dayCell.modelData.day
                  pointSize: Style.fontSizeS
                  font.weight: dayCell.modelData.today ? Style.fontWeightBold : Style.fontWeightRegular
                  color: dayCell.modelData.today ? Color.mOnSecondary : (dayCell.modelData.currentMonth ? Color.mOnSurface : Color.mOnSurfaceVariant)
                  opacity: dayCell.modelData.currentMonth ? 1.0 : 0.4
                  features: ({
                      "tnum": 1
                    })
                }
              }
            }
          }
        }
      }
    }
  }
}
