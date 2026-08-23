import QtQuick

// User card. There is no avatar image on this system (~/.face absent), so the
// avatar is the first initial on an accent circle; it falls back cleanly if an
// image is added later via `avatarSource`.
Card {
  id: root
  property string userName: "liam"
  property string hostName: "Kelper"
  property string distro: "Arch Linux"
  property url avatarSource: ""

  implicitWidth: Theme.profileCardW
  implicitHeight: Theme.weatherCardH
  radius: Theme.radiusXL

  Row {
    anchors.fill: parent
    anchors.margins: Theme.gapL
    spacing: Theme.gapL

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.avatarSize
      height: Theme.avatarSize
      radius: width / 2
      color: Theme.accent

      Text {
        anchors.centerIn: parent
        visible: avatar.status !== Image.Ready
        text: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : "?"
        color: Theme.bgDeep
        font.bold: true
        font.pixelSize: Theme.fs(28)
      }

      Image {
        id: avatar
        anchors.fill: parent
        source: root.avatarSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: status === Image.Ready
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1

      Text {
        text: root.userName
        color: Theme.text
        font.bold: true
        font.pixelSize: Theme.fs(18)
      }
      Text {
        text: "@" + root.hostName
        color: Theme.textDim
        font.pixelSize: Theme.fs(12)
      }
      Item { width: 1; height: Theme.gapS }
      Text {
        text: root.distro
        color: Theme.textDim
        font.pixelSize: Theme.fs(12)
      }
      Text {
        text: "up " + SysState.fmtUptime(SysState.uptimeSeconds)
        color: Theme.textMuted
        font.pixelSize: Theme.fs(11)
      }
    }
  }
}
