import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Hosted by NPluginSettingsPopup, which calls saveSettings() on Apply.
ColumnLayout {
  id: root

  property var pluginApi: null

  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

  // Edit buffers. Each reads the same key string it is written back to below —
  // wallcards reads icon_color but writes iconColor, so its colour picker silently
  // resets on every save. Keep these symmetric.
  property string editFormat: pluginApi?.pluginSettings?.format ?? root.defaults.format ?? "h:mm AP"
  property string editTimezone: pluginApi?.pluginSettings?.timezone ?? root.defaults.timezone ?? "local"
  property string editClockColor: pluginApi?.pluginSettings?.clockColor ?? root.defaults.clockColor ?? "none"
  property string editTooltipFormat: pluginApi?.pluginSettings?.tooltipFormat ?? root.defaults.tooltipFormat ?? "HH:mm ddd, MMM dd"

  function saveSettings() {
    if (!pluginApi || !pluginApi.pluginSettings) {
      Logger.e("CalendarClock", "Cannot save: pluginApi or pluginSettings is null");
      return;
    }

    pluginApi.pluginSettings.format = root.editFormat;
    pluginApi.pluginSettings.timezone = root.editTimezone;
    pluginApi.pluginSettings.clockColor = root.editClockColor;
    pluginApi.pluginSettings.tooltipFormat = root.editTooltipFormat;

    // Drop the cached offset so the new zone is re-resolved rather than reusing
    // the previous zone's offset until the next probe returns.
    pluginApi.pluginSettings.cachedOffset = 0;

    pluginApi.saveSettings();
    Logger.i("CalendarClock", "Settings saved");
  }

  Layout.rightMargin: Style.marginL
  spacing: Style.marginL

  NComboBox {
    Layout.fillWidth: true
    label: root.pluginApi?.tr("settings.format.label")
    description: root.pluginApi?.tr("settings.format.description")
    currentKey: root.editFormat
    defaultValue: root.defaults.format
    model: [
      {
        "key": "h:mm AP",
        "name": root.pluginApi?.tr("formats.h12")
      },
      {
        "key": "HH:mm",
        "name": root.pluginApi?.tr("formats.h24")
      },
      {
        "key": "ddd, MMM d",
        "name": root.pluginApi?.tr("formats.short-date")
      },
      {
        "key": "yyyy-MM-dd",
        "name": root.pluginApi?.tr("formats.iso-date")
      }
    ]

    onSelected: key => root.editFormat = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: root.pluginApi?.tr("settings.timezone.label")
    description: root.pluginApi?.tr("settings.timezone.description")
    currentKey: root.editTimezone
    defaultValue: root.defaults.timezone
    model: [
      {
        "key": "local",
        "name": root.pluginApi?.tr("timezones.local")
      },
      {
        "key": "America/New_York",
        "name": "America/New_York"
      },
      {
        "key": "America/Denver",
        "name": "America/Denver"
      },
      {
        "key": "America/Los_Angeles",
        "name": "America/Los_Angeles"
      },
      {
        "key": "America/Phoenix",
        "name": "America/Phoenix"
      },
      {
        "key": "UTC",
        "name": "UTC"
      }
    ]

    onSelected: key => root.editTimezone = key
  }

  NDivider {
    Layout.fillWidth: true
  }

  NComboBox {
    Layout.fillWidth: true
    label: root.pluginApi?.tr("settings.clock-color.label")
    description: root.pluginApi?.tr("settings.clock-color.description")
    currentKey: root.editClockColor
    defaultValue: root.defaults.clockColor
    model: Color.colorKeyModel

    onSelected: key => root.editClockColor = key
  }

  NTextInput {
    Layout.fillWidth: true
    label: root.pluginApi?.tr("settings.tooltip-format.label")
    description: root.pluginApi?.tr("settings.tooltip-format.description")
    text: root.editTooltipFormat
    defaultValue: root.defaults.tooltipFormat
    placeholderText: "HH:mm ddd, MMM dd"

    onEditingFinished: root.editTooltipFormat = text
  }
}
