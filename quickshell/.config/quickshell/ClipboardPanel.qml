import QtQuick
import Quickshell

// Clipboard history popup. Follows the popup conventions of the other panels:
// anchored under its bar item, focus-grabbing, Escape closes, visible only on
// the screen whose icon was clicked.
//
// Selecting an entry only restores it to the clipboard; pasting stays an explicit
// Super+V, so a selection can never land in the wrong window.
PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  visible: ClipboardState.panelVisible
        && ClipboardState.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  implicitWidth: Theme.fs(520)
  implicitHeight: Theme.fs(500)

  function commit() {
    if (ClipboardState.selected) {
      ClipboardState.restore(ClipboardState.selected)
      ClipboardState.panelVisible = false
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
    radius: Theme.radiusXL

    Item {
      anchors.fill: parent
      anchors.margins: Theme.drawerPadding

      // --- header ---
      Text {
        id: heading
        anchors.left: parent.left
        anchors.top: parent.top
        text: "Clipboard"
        color: Theme.text
        font.bold: true
        font.pixelSize: Theme.fs(16)
      }

      Rectangle {
        id: clearBtn
        anchors.right: parent.right
        anchors.top: parent.top
        width: clearLabel.implicitWidth + Theme.gapM
        height: Theme.fs(24)
        radius: Theme.radiusS
        color: clearArea.containsMouse ? Theme.accent : Theme.surface

        Text {
          id: clearLabel
          anchors.centerIn: parent
          text: "Clear"
          color: clearArea.containsMouse ? Theme.bgDeep : Theme.text
          font.pixelSize: Theme.fs(11)
        }

        MouseArea {
          id: clearArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: ClipboardState.wipe()
        }
      }

      // --- search ---
      Rectangle {
        id: searchBox
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.topMargin: Theme.gapM
        height: Theme.fs(30)
        radius: Theme.radiusS
        color: Theme.bgDeep
        border.width: 1
        border.color: Theme.surface

        Text {
          id: searchIcon
          anchors.left: parent.left
          anchors.leftMargin: Theme.gapS
          anchors.verticalCenter: parent.verticalCenter
          text: ClipboardState.glyphSearch
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(13)
          color: Theme.textDim
        }

        TextInput {
          id: search
          anchors.left: searchIcon.right
          anchors.leftMargin: Theme.gapS
          anchors.right: parent.right
          anchors.rightMargin: Theme.gapS
          anchors.verticalCenter: parent.verticalCenter
          color: Theme.text
          font.pixelSize: Theme.fs(12)
          selectByMouse: true
          clip: true
          focus: true

          onTextChanged: ClipboardState.query = text

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: search.text === ""
            text: "Search clipboard…"
            color: Theme.textMuted
            font.pixelSize: Theme.fs(12)
          }

          Keys.onEscapePressed: ClipboardState.panelVisible = false
          Keys.onUpPressed: ClipboardState.moveSelection(-1)
          Keys.onDownPressed: ClipboardState.moveSelection(1)
          Keys.onReturnPressed: panel.commit()
          Keys.onEnterPressed: panel.commit()

          // Ctrl+Delete rather than plain Delete: Delete has to stay available
          // for editing the search text, and Ctrl+Delete is what the existing
          // rofi clipboard menu already uses to remove an entry.
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ControlModifier)) {
              if (ClipboardState.selected)
                ClipboardState.remove(ClipboardState.selected)
              event.accepted = true
            }
          }
        }
      }

      // --- status line (errors / empty) ---
      Text {
        id: status
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchBox.bottom
        anchors.topMargin: Theme.gapS
        visible: text !== ""
        wrapMode: Text.WordWrap
        color: ClipboardState.lastError !== "" ? Theme.error : Theme.textMuted
        font.pixelSize: Theme.fs(11)
        text: {
          if (ClipboardState.lastError !== "")
            return ClipboardState.lastError
          if (ClipboardState.entries.length === 0)
            return "Clipboard history is empty"
          if (ClipboardState.filtered.length === 0)
            return "No entries match “" + ClipboardState.query + "”"
          return ""
        }
      }

      // --- entries ---
      ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: status.visible ? status.bottom : searchBox.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: Theme.gapM
        clip: true
        spacing: Theme.gapXS
        model: ClipboardState.filtered
        currentIndex: ClipboardState.selectedIndex
        // Driven from the search field, so the list itself must not steal keys.
        interactive: true
        keyNavigationEnabled: false

        onCurrentIndexChanged: if (currentIndex >= 0) list.positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool isCurrent: index === ClipboardState.selectedIndex

          width: list.width
          height: modelData.isImage ? Theme.fs(74) : Theme.fs(56)
          radius: Theme.radiusM
          color: isCurrent ? Theme.surface : "transparent"
          border.width: 1
          border.color: isCurrent ? Theme.accent : "transparent"

          // Thumbnails are only decoded once a row is actually on screen.
          Component.onCompleted: if (modelData.isImage) ClipboardState.requestThumb(modelData.id)

          Item {
            anchors.fill: parent
            anchors.margins: Theme.gapS

            // type chip / thumbnail
            Rectangle {
              id: kind
              width: modelData.isImage ? Theme.fs(78) : Theme.fs(46)
              height: parent.height
              radius: Theme.radiusS
              color: Theme.bgDeep
              clip: true

              Text {
                anchors.centerIn: parent
                visible: !modelData.isImage || thumb.status !== Image.Ready
                text: modelData.isImage ? ClipboardState.glyphImage : "TEXT"
                font.family: modelData.isImage ? Theme.glyphFamily : Theme.uiFamily
                font.pixelSize: modelData.isImage ? Theme.fs(18) : Theme.fs(9)
                font.bold: !modelData.isImage
                color: Theme.textMuted
              }

              Image {
                id: thumb
                anchors.fill: parent
                visible: modelData.isImage && status === Image.Ready
                source: modelData.isImage ? ClipboardState.thumbFor(modelData.id) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                // Cap the decode so a large screenshot is never decoded at full
                // resolution just to draw a 78px thumbnail.
                sourceSize.width: Theme.fs(160)
                sourceSize.height: Theme.fs(160)
              }
            }

            Column {
              anchors.left: kind.right
              anchors.leftMargin: Theme.gapM
              anchors.right: actions.left
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1

              Text {
                width: parent.width
                text: modelData.isImage
                      ? ("Image · " + modelData.imgFormat + " " + modelData.imgDims)
                      : modelData.preview
                color: Theme.text
                font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: {
                  const rel = ClipboardState.relativeTime(modelData)
                  if (modelData.isImage && modelData.imgSize !== "")
                    return rel !== "" ? modelData.imgSize + " · " + rel : modelData.imgSize
                  return rel
                }
                color: Theme.textMuted
                font.pixelSize: Theme.fs(10)
                elide: Text.ElideRight
              }
            }

            Row {
              id: actions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.gapXS

              IconButton {
                size: Theme.fs(24); glyphSize: Theme.fs(12)
                glyph: modelData.pinned ? ClipboardState.glyphUnpin : ClipboardState.glyphPin
                active: modelData.pinned
                onClicked: ClipboardState.togglePin(modelData.id)
              }
              IconButton {
                size: Theme.fs(24); glyphSize: Theme.fs(12)
                glyph: ClipboardState.glyphDelete
                onClicked: ClipboardState.remove(modelData)
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            // Sits below the action buttons in z-order so pin/delete still work.
            z: -1
            onClicked: {
              ClipboardState.selectedIndex = index
              panel.commit()
            }
          }
        }
      }
    }
  }

  onVisibleChanged: {
    if (visible) {
      search.text = ""
      ClipboardState.query = ""
      ClipboardState.selectedIndex = 0
      ClipboardState.refresh()
      search.forceActiveFocus()
    }
  }
}
