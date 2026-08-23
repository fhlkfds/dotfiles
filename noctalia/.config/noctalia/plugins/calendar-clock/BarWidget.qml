import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Text-only bar capsule. Modelled on the host's Modules/Bar/Widgets/Clock.qml,
// which is the only text-only bar widget in the tree.
Item {
  id: root

  // Injected by BarWidgetLoader._initialProps()
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance ?? null

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  readonly property color textColor: Color.resolveColorKey(mainInstance?.clockColor ?? "none")

  readonly property string label: {
    if (!mainInstance)
      return "";
    return I18n.locale.toString(mainInstance.displayTime, String(mainInstance.format).trim());
  }

  // On a vertical bar the one-line formats won't fit, so stack on spaces.
  readonly property var labelLines: root.isBarVertical ? root.label.split(" ") : [root.label]

  readonly property real contentWidth: root.isBarVertical ? root.capsuleHeight : Math.round(textColumn.implicitWidth + Style.margin2M)
  readonly property real contentHeight: root.isBarVertical ? Math.round(textColumn.implicitHeight + Style.margin2S) : root.capsuleHeight

  // BarWidgetLoader overrides one axis to widen the click area, so the visual
  // capsule re-centres itself inside whatever the loader hands us.
  implicitWidth: root.contentWidth
  implicitHeight: root.contentHeight

  function buildTooltipText() {
    if (!mainInstance)
      return "";
    var fmt = String(mainInstance.tooltipFormat).trim();
    var text = I18n.locale.toString(mainInstance.displayTime, fmt);
    if (!mainInstance.isLocal)
      text += "  ·  " + mainInstance.zoneLabel(mainInstance.timezone);
    return text;
  }

  Rectangle {
    id: visualCapsule

    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent

    radius: Style.radiusL
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    ColumnLayout {
      id: textColumn

      anchors.centerIn: parent
      spacing: -2

      Repeater {
        model: root.labelLines

        NText {
          required property string modelData

          visible: text !== ""
          text: modelData
          pointSize: root.barFontSize
          applyUiScale: false
          color: mouseArea.containsMouse ? Color.mOnHover : root.textColor
          // Tabular numerals: without this the capsule visibly jitters as digits change.
          features: ({
              "tnum": 1
            })
          Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
        }
      }
    }
  }

  MouseArea {
    id: mouseArea

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onEntered: {
      TooltipService.show(root, root.buildTooltipText(), BarService.getTooltipDirection(root.screenName));
      tooltipRefreshTimer.start();
    }

    onExited: {
      tooltipRefreshTimer.stop();
      TooltipService.hide();
    }

    onClicked: mouse => {
      TooltipService.hide();
      if (mouse.button === Qt.LeftButton) {
        pluginApi?.togglePanel(root.screen, root);
      } else if (mouse.button === Qt.RightButton) {
        root.mainInstance?.cycleFormat();
      } else if (mouse.button === Qt.MiddleButton) {
        PanelService.showContextMenu(tzMenu, root, root.screen);
      }
    }
  }

  // Keeps the tooltip ticking while hovered, as the host Clock does.
  Timer {
    id: tooltipRefreshTimer

    interval: 1000
    repeat: true
    onTriggered: {
      if (mouseArea.containsMouse)
        TooltipService.updateText(root.buildTooltipText());
    }
  }

  // Middle-click: timezone picker. Right-click is spent on the format cycle, so
  // the settings entry lives here instead of on its usual right-click.
  NPopupContextMenu {
    id: tzMenu

    model: {
      var items = [];
      if (!root.mainInstance)
        return items;
      var zones = root.mainInstance.zones;
      for (var i = 0; i < zones.length; i++) {
        // Every item carries an icon: an invisible NIcon collapses in the delegate's
        // RowLayout, which would leave the labels ragged.
        items.push({
          "label": root.mainInstance.zoneLabel(zones[i]),
          "action": "tz:" + zones[i],
          "icon": zones[i] === root.mainInstance.timezone ? "circle-dot" : "circle"
        });
      }
      items.push({
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      });
      return items;
    }

    onTriggered: action => {
      // The delegate deliberately does not self-close; both calls are required.
      tzMenu.close();
      PanelService.closeContextMenu(root.screen);

      if (action === "widget-settings") {
        BarService.openPluginSettings(root.screen, root.pluginApi.manifest);
      } else if (action.indexOf("tz:") === 0) {
        root.mainInstance?.setTimezone(action.substring(3));
      }
    }
  }
}
