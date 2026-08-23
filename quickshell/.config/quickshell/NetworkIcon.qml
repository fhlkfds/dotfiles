import QtQuick

Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  required property string screenName

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  readonly property string glyph: {
    if (NetworkState.connType === "ethernet")
      return String.fromCodePoint(0xef44) // fa-ethernet
    if (NetworkState.connType === "wifi") {
      const s = NetworkState.signalPct
      if (s >= 75) return String.fromCodePoint(0xf0928)  // md-wifi_strength_4
      if (s >= 50) return String.fromCodePoint(0xf0925)  // md-wifi_strength_3
      if (s >= 25) return String.fromCodePoint(0xf0922)  // md-wifi_strength_2
      if (s > 0)   return String.fromCodePoint(0xf091f)  // md-wifi_strength_1
      return String.fromCodePoint(0xf05aa)               // md-wifi_off
    }
    return String.fromCodePoint(0xf05aa) // md-wifi_off (no connection)
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.glyph
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: Theme.text
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: {
      if (NetworkState.connType === "wifi")
        NetworkState.openNmtui()
      else
        NetworkState.togglePanel(root.screenName)
    }
  }

  NetworkPanel {
    anchorItem: root
    ownerScreen: root.screenName
  }
}
