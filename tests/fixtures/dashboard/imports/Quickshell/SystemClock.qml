import QtQuick
QtObject {
  enum Precision { Seconds, Minutes, Hours }
  property int precision: SystemClock.Minutes
  property date date: new Date(2026, 9, 3, 18, 30)
}
