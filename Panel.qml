import QtQuick
import QtQuick.Controls
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

  property var allFonts: []
  property var visibleFonts: []
  property string query: ""
  property int cursor: 0
  property string draftFamily: "Inter"
  property string draftWeight: "semibold"

  readonly property bool dirty: {
    if (!root.service || !root.service.config) return false
    var cfg = root.service.config
    if (!cfg.enabled) return true
    return draftFamily !== cfg.family || draftWeight !== cfg.weight
  }
  readonly property bool applying: !!(root.service && root.service.applying)

  function collectFonts() {
    var raw = Qt.fontFamilies() || []
    var skip = { OmarchyShellFont: true, InterBar: true }
    var seen = {}
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var name = String(raw[i] || "").trim()
      if (!name || skip[name] || seen[name]) continue
      if (name.indexOf("Awesome") !== -1 || name.indexOf("Nerd Font") !== -1) continue
      seen[name] = true
      out.push(name)
    }
    out.sort(function(a, b) { return a.localeCompare(b) })
    allFonts = out
    applyQuery()
  }

  function applyQuery() {
    var q = query.trim().toLowerCase()
    var src = allFonts
    var out = []
    for (var i = 0; i < src.length; i++) {
      if (!q || String(src[i]).toLowerCase().indexOf(q) !== -1) out.push(src[i])
    }
    visibleFonts = out
    var selected = out.indexOf(draftFamily)
    cursor = selected >= 0 ? selected : 0
    if (fontList && out.length)
      fontList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function moveCursor(dy) {
    if (!visibleFonts.length) return
    cursor = Math.max(0, Math.min(visibleFonts.length - 1, cursor + dy))
    fontList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function chooseCursor() {
    if (cursor >= 0 && cursor < visibleFonts.length)
      draftFamily = visibleFonts[cursor]
  }

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
    query = ""
    collectFonts()
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
      blocked: weightPicker.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.chooseCursor()
      onDeleteRequested: {
        root.query = root.query.slice(0, Math.max(0, root.query.length - 1))
        root.applyQuery()
      }
      onTextKey: function(t) {
        if (!t || t === "j" || t === "k" || t === "h" || t === "l") return
        root.query += t
        root.applyQuery()
      }

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
          text: query.length ? ("Filter: " + query) : "Type to filter · j/k to move · Enter to select"
          color: root.barForeground
          opacity: 0.7
          wrapMode: Text.WordWrap
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        ListView {
          id: fontList
          width: parent.width
          height: Style.space(240)
          clip: true
          spacing: Style.space(4)
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          currentIndex: root.cursor
          model: root.visibleFonts

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property string modelData
            required property int index
            width: ListView.view.width
            height: Style.space(28)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: modelData === root.draftFamily
                ? Style.selectedFillFor(root.barForeground, Color.accent)
                : (index === root.cursor ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent")
            }

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              verticalAlignment: Text.AlignVCenter
              text: modelData
              elide: Text.ElideRight
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.cursor = index
              onClicked: {
                root.cursor = index
                root.draftFamily = modelData
              }
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
          onChanged: function(value) { root.draftWeight = value }
        }

        Text {
          width: parent.width
          text: draftFamily + " · " + draftWeight
          color: root.barForeground
          font.family: draftFamily
          font.weight: root.qtWeight(draftWeight)
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
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
