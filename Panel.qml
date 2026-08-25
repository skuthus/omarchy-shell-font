import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "skuthus.shell-font"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var service: {
    if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
      return root.bar.shell.serviceFor("skuthus.shell-font")
    return null
  }

  readonly property var weightOptions: [
    { value: "thin", label: "Thin" },
    { value: "extralight", label: "ExtraLight" },
    { value: "light", label: "Light" },
    { value: "regular", label: "Regular" },
    { value: "medium", label: "Medium" },
    { value: "semibold", label: "SemiBold" },
    { value: "bold", label: "Bold" },
    { value: "extrabold", label: "ExtraBold" },
    { value: "black", label: "Black" }
  ]

  readonly property var fontOptions: {
    var raw = Qt.fontFamilies() || []
    var skip = {
      "OmarchyShellFont": true,
      "InterBar": true
    }
    var seen = {}
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var name = String(raw[i] || "").trim()
      if (!name || skip[name] || seen[name]) continue
      seen[name] = true
      out.push(name)
    }
    out.sort(function(a, b) { return a.localeCompare(b) })
    return out
  }

  property string draftFamily: "Inter"
  property string draftWeight: "semibold"
  property bool draftReady: false

  readonly property bool dirty: {
    if (!root.service || !root.service.config) return draftReady
    var cfg = root.service.config
    if (!cfg.enabled) return true
    return draftFamily !== cfg.family || draftWeight !== cfg.weight
  }
  readonly property bool applying: !!(root.service && root.service.applying)

  function qtWeight(name) {
    switch (String(name)) {
      case "thin": return Font.Thin
      case "extralight": return Font.ExtraLight
      case "light": return Font.Light
      case "medium": return Font.Medium
      case "semibold": return Font.DemiBold
      case "bold": return Font.Bold
      case "extrabold": return Font.ExtraBold
      case "black": return Font.Black
      default: return Font.Normal
    }
  }

  function syncFromService() {
    if (!root.service || !root.service.config) return
    var cfg = root.service.config
    draftFamily = cfg.family && cfg.family !== "monospace" ? cfg.family : "Inter"
    draftWeight = cfg.weight || "semibold"
    draftReady = true
  }

  function applyDraft() {
    if (!root.service) return
    root.service.saveConfig({
      enabled: true,
      family: draftFamily,
      weight: draftWeight
    }, true)
  }

  function resetToMono() {
    if (!root.service) return
    root.service.saveConfig({
      enabled: false,
      family: "monospace",
      weight: "regular"
    }, false)
    draftReady = true
  }

  function open() {
    syncFromService()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  onOpenedChanged: if (opened) syncFromService()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      enabled: !fontSearch.activeFocus && !weightPicker.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Shell font"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          width: parent.width
          text: "Bar and shell UI. Terminals keep the system monospace font."
          color: root.barForeground
          opacity: 0.7
          wrapMode: Text.WordWrap
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          text: "Family"
          color: root.barForeground
          opacity: 0.7
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: fontSearch
          width: parent.width
          placeholderText: "Search fonts..."
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
        }

        ListView {
          id: fontList
          width: parent.width
          height: Style.space(420)
          clip: true
          spacing: Style.spacing.xxs
          boundsBehavior: Flickable.StopAtBounds
          reuseItems: true
          currentIndex: -1

          readonly property var filtered: {
            var q = String(fontSearch.text || "").trim().toLowerCase()
            var src = root.fontOptions
            if (!q) return src
            var out = []
            for (var i = 0; i < src.length; i++) {
              if (String(src[i]).toLowerCase().indexOf(q) !== -1) out.push(src[i])
            }
            return out
          }

          model: filtered

          QQC.ScrollBar.vertical: QQC.ScrollBar {
            policy: fontList.contentHeight > fontList.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AsNeeded
          }

          delegate: Rectangle {
            required property string modelData
            required property int index
            width: fontList.width
            height: Style.spacing.popupRowHeight
            radius: Style.cornerRadius
            color: modelData === root.draftFamily
              ? Style.selectedFillFor(root.barForeground, Color.accent)
              : (index === fontList.currentIndex ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent")

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              verticalAlignment: Text.AlignVCenter
              text: modelData
              elide: Text.ElideRight
              color: root.barForeground
              font.family: modelData
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: fontList.currentIndex = parent.index
              onClicked: root.draftFamily = parent.modelData
            }
          }
        }

        Dropdown {
          id: weightPicker
          width: parent.width
          label: "Weight"
          value: root.draftWeight
          options: root.weightOptions
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.barForeground
          onChanged: function(value) {
            root.draftWeight = value
          }
        }

        Rectangle {
          width: parent.width
          height: previewCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Style.normalFill
          border.width: Style.normalBorderWidth
          border.color: Style.normalBorderColor

          Column {
            id: previewCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(10)
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: "8:24 AM   12345"
              color: root.barForeground
              font.family: root.draftFamily
              font.weight: root.qtWeight(root.draftWeight)
              font.pixelSize: Style.font.title
            }

            Text {
              width: parent.width
              text: root.draftFamily + " · " + root.draftWeight
              color: root.barForeground
              opacity: 0.65
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Button {
          width: parent.width
          text: applying ? "Applying…" : (dirty ? "Apply" : "Applied")
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.barForeground
          bordered: true
          selected: dirty && !applying
          enabled: dirty && !applying
          onClicked: root.applyDraft()
        }

        Button {
          width: parent.width
          text: "Use system monospace"
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.barForeground
          bordered: true
          onClicked: root.resetToMono()
        }
      }
    }
  }
}
