import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Settings
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  readonly property bool compactMode: widgetSettings.compactMode !== undefined ? widgetSettings.compactMode : widgetMetadata.compactMode
  readonly property bool usePrimaryColor: widgetSettings.usePrimaryColor !== undefined ? widgetSettings.usePrimaryColor : widgetMetadata.usePrimaryColor
  readonly property bool useMonospaceFont: widgetSettings.useMonospaceFont !== undefined ? widgetSettings.useMonospaceFont : widgetMetadata.useMonospaceFont
  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuCoreChart: (widgetSettings.showCpuCoreChart !== undefined) ? widgetSettings.showCpuCoreChart : (widgetMetadata.showCpuCoreChart || false)
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showCpuTempGauge: (widgetSettings.showCpuTempGauge !== undefined) ? widgetSettings.showCpuTempGauge : (widgetMetadata.showCpuTempGauge || false)
  readonly property bool showGpuTemp: (widgetSettings.showGpuTemp !== undefined) ? widgetSettings.showGpuTemp : widgetMetadata.showGpuTemp
  readonly property bool showCoolantTemp: (widgetSettings.showCoolantTemp !== undefined) ? widgetSettings.showCoolantTemp : widgetMetadata.showCoolantTemp
  readonly property bool coolantUseCompactMode: (widgetSettings.coolantUseCompactMode !== undefined) ? widgetSettings.coolantUseCompactMode : (widgetMetadata.coolantUseCompactMode || false)
  readonly property bool showCpuWatt: (widgetSettings.showCpuWatt !== undefined) ? widgetSettings.showCpuWatt : widgetMetadata.showCpuWatt
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats
  readonly property bool showDiskUsage: (widgetSettings.showDiskUsage !== undefined) ? widgetSettings.showDiskUsage : widgetMetadata.showDiskUsage
  readonly property bool showLoadAverage: (widgetSettings.showLoadAverage !== undefined) ? widgetSettings.showLoadAverage : widgetMetadata.showLoadAverage
  readonly property string diskPath: (widgetSettings.diskPath !== undefined) ? widgetSettings.diskPath : widgetMetadata.diskPath
  readonly property string fontFamily: useMonospaceFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault

  readonly property real iconSize: Style.toOdd(Style.capsuleHeight * 0.48)
  readonly property int itemSpacing: 5
  readonly property real miniGaugeWidth: Math.max(3, Style.toOdd(root.iconSize * 0.25))
  readonly property real textSize: Math.max(7, iconSize * barScaling * 0.6 * (isVertical ? 0.85 : 1.0))

  function openExternalMonitor() {
    Quickshell.execDetached(["sh", "-c", Settings.data.systemMonitor.externalMonitor]);
  }

  // Build comprehensive tooltip text with all stats
  function buildTooltipText() {
    let lines = [];

    // CPU
    lines.push(`${I18n.tr("system-monitor.cpu-usage")}: ${Math.round(SystemStatService.cpuUsage)}%`);
    if (SystemStatService.cpuTemp > 0) {
      lines.push(`${I18n.tr("system-monitor.cpu-temp")}: ${Math.round(SystemStatService.cpuTemp)}°C`);
    }

    // GPU (if available)
    if (SystemStatService.gpuAvailable) {
      lines.push(`${I18n.tr("system-monitor.gpu-temp")}: ${Math.round(SystemStatService.gpuTemp)}°C`);
    }

    // Load Average
    if (SystemStatService.loadAvg1 >= 0) {
      lines.push(`${I18n.tr("system-monitor.load-average")}: ${SystemStatService.loadAvg1.toFixed(2)} ${SystemStatService.loadAvg5.toFixed(2)} ${SystemStatService.loadAvg15.toFixed(2)}`);
    }

    // Coolant (if configured)
    if (SystemStatService.coolantTemp > 0) {
      lines.push(`Coolant: ${Number(SystemStatService.coolantTemp).toFixed(1)}°C`);
    }

    // Memory
    lines.push(`${I18n.tr("common.memory")}: ${Math.round(SystemStatService.memPercent)}% (${SystemStatService.formatMemoryGb(SystemStatService.memGb)})`);

    // Network
    lines.push(`${I18n.tr("system-monitor.download-speed")}: ${SystemStatService.formatSpeed(SystemStatService.rxSpeed)}`);
    lines.push(`${I18n.tr("system-monitor.upload-speed")}: ${SystemStatService.formatSpeed(SystemStatService.txSpeed)}`);

    // Disk
    const diskPercent = SystemStatService.diskPercents[diskPath];
    if (diskPercent !== undefined) {
      const usedGb = SystemStatService.diskUsedGb[diskPath] || 0;
      const sizeGb = SystemStatService.diskSizeGb[diskPath] || 0;
      lines.push(`${I18n.tr("system-monitor.disk")}: ${usedGb.toFixed(1)}G / ${sizeGb.toFixed(1)}G (${diskPercent}%)`);
    }

    return lines.join("\n");
  }

  readonly property color textColor: usePrimaryColor ? Color.mPrimary : Color.mOnSurface

  // Visibility-aware warning/critical states (delegates to service)
  readonly property bool cpuWarning: showCpuUsage && SystemStatService.cpuWarning
  readonly property bool cpuCritical: showCpuUsage && SystemStatService.cpuCritical
  readonly property bool tempWarning: showCpuTemp && SystemStatService.tempWarning
  readonly property bool tempCritical: showCpuTemp && SystemStatService.tempCritical
  readonly property bool gpuWarning: showGpuTemp && SystemStatService.gpuWarning
  readonly property bool gpuCritical: showGpuTemp && SystemStatService.gpuCritical
  readonly property bool coolantWarning: showCoolantTemp && SystemStatService.coolantWarning
  readonly property bool coolantCritical: showCoolantTemp && SystemStatService.coolantCritical
  readonly property bool memWarning: showMemoryUsage && SystemStatService.memWarning
  readonly property bool memCritical: showMemoryUsage && SystemStatService.memCritical
  readonly property bool diskWarning: showDiskUsage && SystemStatService.isDiskWarning(diskPath)
  readonly property bool diskCritical: showDiskUsage && SystemStatService.isDiskCritical(diskPath)

  anchors.centerIn: parent
  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(mainGrid.implicitWidth + Style.marginM * 2)
  implicitHeight: isVertical ? Math.round(mainGrid.implicitHeight + Style.marginM * 2) : Style.capsuleHeight
  radius: Style.radiusM
  color: Style.capsuleColor
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  MouseArea {
    id: tooltipArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    onClicked: mouse => {
                 if (mouse.button === Qt.LeftButton) {
                   PanelService.getPanel("systemStatsPanel", screen)?.toggle(root);
                   TooltipService.hide();
                 } else if (mouse.button === Qt.RightButton) {
                   TooltipService.hide();
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.showContextMenu(contextMenu);
                     contextMenu.openAtItem(root, screen);
                   }
                 } else if (mouse.button === Qt.MiddleButton) {
                   TooltipService.hide();
                   openExternalMonitor();
                 }
               }
    onEntered: {
      TooltipService.show(root, buildTooltipText(), BarService.getTooltipDirection());
      tooltipRefreshTimer.start();
    }
    onExited: {
      tooltipRefreshTimer.stop();
      TooltipService.hide();
    }
  }

  Timer {
    id: tooltipRefreshTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (tooltipArea.containsMouse) {
        TooltipService.updateText(buildTooltipText());
      }
    }
  }

  // Mini gauge component for compact mode, vertical gauge that fills from bottom
  Component {
    id: miniGaugeComponent

    Rectangle {
      id: miniGauge
      property real ratio: 0 // 0..1
      property color statColor: Color.mPrimary // Color based on warning/critical state

      width: miniGaugeWidth
      height: iconSize
      radius: width / 2
      color: Color.mOutline

      // Fill that grows from bottom
      Rectangle {
        property real fillHeight: parent.height * Math.min(1, Math.max(0, miniGauge.ratio))
        width: parent.width
        height: fillHeight
        radius: parent.radius
        color: miniGauge.statColor
        anchors.bottom: parent.bottom

        Behavior on fillHeight {
          enabled: !Settings.data.general.animationDisabled
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutCubic
          }
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }

  GridLayout {
    id: mainGrid
    anchors.centerIn: parent
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: isVertical ? -1 : 1
    columns: isVertical ? 1 : -1
    rowSpacing: isVertical ? Style.marginL : 0
    columnSpacing: isVertical ? 0 : (Style.marginM)

    // CPU Usage Component
    Item {
      id: cpuUsageContainer
      implicitWidth: cpuUsageContent.implicitWidth
      implicitHeight: cpuUsageContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuUsage

      GridLayout {
        id: cpuUsageContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: itemSpacing

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "cpu-usage"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: (cpuWarning || cpuCritical) ? SystemStatService.cpuColor : Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: `${Math.round(SystemStatService.cpuUsage)}%`
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: (cpuWarning || cpuCritical) ? SystemStatService.cpuColor : textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode (hide if core chart is shown)
        Loader {
          active: compactMode && !showCpuCoreChart
          visible: compactMode && !showCpuCoreChart
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => SystemStatService.cpuUsage / 100);
            item.statColor = Qt.binding(() => SystemStatService.cpuColor);
          }
        }

        // CPU Core Chart (per-core usage bars) - 2 rows: 0-15 top, 16-31 bottom
        Item {
          id: cpuCoreChartContainer
          readonly property int coreCount: SystemStatService.coreUsages.length
          readonly property int halfCount: Math.ceil(coreCount / 2)
          readonly property real rowHeight: (Style.capsuleHeight * 0.85 - 2) / 2  // 2px gap between rows
          readonly property real barWidth: 3
          implicitWidth: halfCount * barWidth + (halfCount - 1) * 1  // bars + spacing
          implicitHeight: rowHeight * 2 + 2  // two rows + gap
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1
          visible: showCpuCoreChart && coreCount > 0

          Column {
            anchors.centerIn: parent
            spacing: 2

            // Top row: cores 0 to halfCount-1
            Row {
              spacing: 1
              height: cpuCoreChartContainer.rowHeight

              Repeater {
                model: cpuCoreChartContainer.halfCount

                Rectangle {
                  width: cpuCoreChartContainer.barWidth
                  height: parent.height
                  radius: width / 2
                  color: "transparent"

                  // System CPU (red) - bottom
                  Rectangle {
                    readonly property real systemUsage: SystemStatService.coreSystemUsages[index] || 0
                    property real fillHeight: parent.height * Math.min(1, Math.max(0, systemUsage / 100))
                    width: parent.width
                    height: fillHeight
                    radius: parent.radius
                    color: "#ff5555"
                    anchors.bottom: parent.bottom

                    Behavior on fillHeight {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  // User CPU (blue) - on top of system
                  Rectangle {
                    readonly property real userUsage: SystemStatService.coreUserUsages[index] || 0
                    readonly property real systemUsage: SystemStatService.coreSystemUsages[index] || 0
                    property real systemHeight: parent.height * Math.min(1, Math.max(0, systemUsage / 100))
                    property real fillHeight: parent.height * Math.min(1, Math.max(0, userUsage / 100))
                    width: parent.width
                    height: fillHeight
                    radius: parent.radius
                    color: "#5599ff"
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: systemHeight

                    Behavior on fillHeight {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.OutCubic
                      }
                    }
                    Behavior on anchors.bottomMargin {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.OutCubic
                      }
                    }
                  }
                }
              }
            }

            // Bottom row: cores halfCount to coreCount-1
            Row {
              spacing: 1
              height: cpuCoreChartContainer.rowHeight

              Repeater {
                model: cpuCoreChartContainer.coreCount - cpuCoreChartContainer.halfCount

                Rectangle {
                  width: cpuCoreChartContainer.barWidth
                  height: parent.height
                  radius: width / 2
                  color: "transparent"

                  // System CPU (red) - bottom
                  Rectangle {
                    readonly property real systemUsage: SystemStatService.coreSystemUsages[cpuCoreChartContainer.halfCount + index] || 0
                    property real fillHeight: parent.height * Math.min(1, Math.max(0, systemUsage / 100))
                    width: parent.width
                    height: fillHeight
                    radius: parent.radius
                    color: "#ff5555"
                    anchors.bottom: parent.bottom

                    Behavior on fillHeight {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  // User CPU (blue) - on top of system
                  Rectangle {
                    readonly property real userUsage: SystemStatService.coreUserUsages[cpuCoreChartContainer.halfCount + index] || 0
                    readonly property real systemUsage: SystemStatService.coreSystemUsages[cpuCoreChartContainer.halfCount + index] || 0
                    property real systemHeight: parent.height * Math.min(1, Math.max(0, systemUsage / 100))
                    property real fillHeight: parent.height * Math.min(1, Math.max(0, userUsage / 100))
                    width: parent.width
                    height: fillHeight
                    radius: parent.radius
                    color: "#5599ff"
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: systemHeight

                    Behavior on fillHeight {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.OutCubic
                      }
                    }
                    Behavior on anchors.bottomMargin {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.OutCubic
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // CPU Temperature Component
    Item {
      id: cpuTempContainer
      implicitWidth: cpuTempContent.implicitWidth
      implicitHeight: cpuTempContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuTemp

      GridLayout {
        id: cpuTempContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: itemSpacing

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "cpu-temperature"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: (tempWarning || tempCritical) ? SystemStatService.tempColor : Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: `${Math.round(SystemStatService.cpuTemp)}°`
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: (tempWarning || tempCritical) ? SystemStatService.tempColor : textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode, mini gauge (to the right of icon)
        Loader {
          active: compactMode && showCpuTempGauge
          visible: compactMode && showCpuTempGauge
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => SystemStatService.cpuTemp / 100);
            item.statColor = Qt.binding(() => SystemStatService.tempColor);
          }
        }
      }
    }

    // GPU Temperature Component
    Item {
      id: gpuTempContainer
      implicitWidth: gpuTempContent.implicitWidth
      implicitHeight: gpuTempContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showGpuTemp && SystemStatService.gpuAvailable

      GridLayout {
        id: gpuTempContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: itemSpacing

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "gpu-temperature"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: (gpuWarning || gpuCritical) ? SystemStatService.gpuColor : Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: `${Math.round(SystemStatService.gpuTemp)}°`
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: (gpuWarning || gpuCritical) ? SystemStatService.gpuColor : textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => SystemStatService.gpuTemp / 100);
            item.statColor = Qt.binding(() => SystemStatService.gpuColor);
          }
        }
      }
    }

    // Load Average Component
    Item {
      id: loadAvgContainer
      implicitWidth: loadAvgContent.implicitWidth
      implicitHeight: loadAvgContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showLoadAverage && SystemStatService.nproc > 0 && SystemStatService.loadAvg1 > 0

      GridLayout {
        id: loadAvgContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "weight"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: SystemStatService.loadAvg1.toFixed(1)
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => Math.min(1, SystemStatService.loadAvg1 / SystemStatService.nproc));
            item.statColor = Qt.binding(() => Color.mPrimary);
          }
        }
      }
    }

    // Coolant Temperature Component
    Item {
      id: coolantTempContainer
      implicitWidth: coolantTempContent.implicitWidth
      implicitHeight: coolantTempContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCoolantTemp

      GridLayout {
        id: coolantTempContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "droplet"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: (coolantWarning || coolantCritical) ? SystemStatService.coolantColor : Color.mOnSurface
          }
        }

        // Text mode (show when not using compact mode, or always if coolantUseCompactMode is false)
        NText {
          visible: !compactMode || !coolantUseCompactMode
          text: Number(SystemStatService.coolantTemp).toFixed(1) + "°"
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: (coolantWarning || coolantCritical) ? SystemStatService.coolantColor : textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode gauge (only when coolantUseCompactMode is true)
        Loader {
          active: compactMode && coolantUseCompactMode
          visible: compactMode && coolantUseCompactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => SystemStatService.coolantTemp / 100);
            item.statColor = Qt.binding(() => SystemStatService.coolantColor);
          }
        }
      }
    }

    // CPU Watt Component
    Item {
      id: cpuWattContainer
      implicitWidth: cpuWattContent.implicitWidth
      implicitHeight: cpuWattContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuWatt

      GridLayout {
        id: cpuWattContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "bolt"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: {
            const watt = Number(SystemStatService.cpuWatt);
            if (!watt || isNaN(watt)) {
              return "--";
            }
            return `${Math.round(watt)}W`;
          }
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode - show as mini gauge (ratio based on typical max of 150W)
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => Math.min(1, SystemStatService.cpuWatt / 150));
            item.statColor = Qt.binding(() => Color.mPrimary);
          }
        }
      }
    }

    // Memory Usage Component
    Item {
      id: memoryContainer
      implicitWidth: memoryContent.implicitWidth
      implicitHeight: memoryContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showMemoryUsage

      GridLayout {
        id: memoryContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: itemSpacing

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "memory"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: (memWarning || memCritical) ? SystemStatService.memColor : Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: showMemoryAsPercent ? `${Math.round(SystemStatService.memPercent)}%` : SystemStatService.formatMemoryGb(SystemStatService.memGb)
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: (memWarning || memCritical) ? SystemStatService.memColor : textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => SystemStatService.memPercent / 100);
            item.statColor = Qt.binding(() => SystemStatService.memColor);
          }
        }
      }
    }

    // Network Download Speed Component
    Item {
      implicitWidth: downloadContent.implicitWidth
      implicitHeight: downloadContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: downloadContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: itemSpacing

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "download-speed"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.rxSpeed) : SystemStatService.formatSpeed(SystemStatService.rxSpeed)
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => SystemStatService.rxRatio);
          }
        }
      }
    }

    // Network Upload Speed Component
    Item {
      implicitWidth: uploadContent.implicitWidth
      implicitHeight: uploadContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: uploadContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: itemSpacing

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "upload-speed"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.txSpeed) : SystemStatService.formatSpeed(SystemStatService.txSpeed)
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => SystemStatService.txRatio);
          }
        }
      }
    }

    // Disk Usage Component (primary drive)
    Item {
      id: diskContainer
      implicitWidth: diskContent.implicitWidth
      implicitHeight: diskContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showDiskUsage

      GridLayout {
        id: diskContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: itemSpacing

        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: compactMode ? iconSize : Style.capsuleHeight
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0

          NIcon {
            icon: "storage"
            pointSize: iconSize
            applyUiScale: false
            x: Style.pixelAlignCenter(parent.width, width)
            y: Style.pixelAlignCenter(parent.height, contentHeight)
            color: (diskWarning || diskCritical) ? SystemStatService.getDiskColor(diskPath) : Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: SystemStatService.diskPercents[diskPath] ? `${SystemStatService.diskPercents[diskPath]}%` : "n/a"
          family: fontFamily
          pointSize: Style.barFontSize
          applyUiScale: false
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: (diskWarning || diskCritical) ? SystemStatService.getDiskColor(diskPath) : textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.ratio = Qt.binding(() => (SystemStatService.diskPercents[diskPath] ?? 0) / 100);
            item.statColor = Qt.binding(() => SystemStatService.getDiskColor(diskPath));
          }
        }
      }
    }
  }
}
