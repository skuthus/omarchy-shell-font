import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string query: ""
  property var allFonts: []
  property var visibleFonts: []
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

  readonly property var weightOptions: [
    { value: "regular", label: "Regular" },
    { value: "medium", label: "Medium" },
    { value: "semibold", label: "SemiBold" },
    { value: "bold", label: "Bold" },
    { value: "extrabold", label: "ExtraBold" }
  ]

  function open(payloadJson) {
    syncFromService()
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "skuthus.shell-font")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function syncFromService() {
    if (root.service && root.service.config) {
      var cfg = root.service.config
      draftFamily = cfg.family && cfg.family !== "monospace" ? cfg.family : "Inter"
      draftWeight = cfg.weight || "semibold"
    }
    query = ""
    collectFonts()
  }

  function collectFonts() {
    var raw = Qt.fontFamilies() || []
    var skip = { OmarchyShellFont: true, InterBar: true }
    var seen = {}
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var name = String(raw[i] || "").trim()
      if (!name || skip[name] || seen[name]) continue
      if (name.indexOf("Awesome") !== -1) continue
      seen[name] = true
      out.push(name)
    }
    out.sort(function(a, b) { return a.localeCompare(b) })
    allFonts = out
    applyQuery()
  }

  function applyQuery() {
    var q = query.trim().toLowerCase()
    var out = []
    for (var i = 0; i < allFonts.length; i++) {
      if (!q || String(allFonts[i]).toLowerCase().indexOf(q) !== -1) out.push(allFonts[i])
    }
    visibleFonts = out
    var selected = out.indexOf(draftFamily)
    cursor = selected >= 0 ? selected : 0
    Qt.callLater(function() {
      if (fontList && out.length)
        fontList.positionViewAtIndex(cursor, ListView.Contain)
    })
  }

  function moveCursor(dy) {
    if (!visibleFonts.length) return
    cursor = Math.max(0, Math.min(visibleFonts.length - 1, cursor + dy))
    if (fontList) fontList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function chooseCursor() {
    if (cursor >= 0 && cursor < visibleFonts.length)
      draftFamily = visibleFonts[cursor]
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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-shell-font"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(420), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.query.length) { root.query = ""; root.applyQuery() }
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.query)) {
            root.query = Util.editedFilter(event, root.query)
            root.applyQuery()
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.text === "j") {
            root.moveCursor(1); event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            root.moveCursor(-1); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.chooseCursor(); event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32) {
            root.query += event.text
            root.applyQuery()
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Shell font"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          width: parent.width
          text: root.query.length ? root.query : "Type to filter"
          color: Color.menu.text
          opacity: root.query.length ? 1 : 0.55
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }

        ListView {
          id: fontList
          width: parent.width
          height: parent.height - Style.space(220)
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          interactive: true
          currentIndex: root.cursor
          model: root.visibleFonts

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: Item {
            required property string modelData
            required property int index
            width: ListView.view.width
            height: Style.space(28)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: modelData === root.draftFamily
                ? Color.menu.selectedBackground
                : (index === root.cursor ? Style.hoverFillFor(Color.menu.text, Color.accent) : "transparent")
            }

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              verticalAlignment: Text.AlignVCenter
              text: modelData
              elide: Text.ElideRight
              color: modelData === root.draftFamily ? Color.menu.selectedText : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.cursor = index
              onClicked: {
                root.cursor = index
                root.draftFamily = modelData
                keyCatcher.forceActiveFocus()
              }
            }
          }
        }

        ButtonGroup {
          width: parent.width
          value: root.draftWeight
          options: root.weightOptions
          fontFamily: Style.font.menuFamily
          foreground: Color.menu.text
          onChanged: function(value) { root.draftWeight = value }
        }

        Text {
          width: parent.width
          text: root.draftFamily + " · " + root.draftWeight
          color: Color.menu.text
          font.family: root.draftFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
        }

        Button {
          width: parent.width
          text: root.applying ? "Applying…" : (root.dirty ? "Apply" : "Applied")
          fontFamily: Style.font.menuFamily
          foreground: Color.menu.text
          bordered: true
          selected: root.dirty && !root.applying
          enabled: root.dirty && !root.applying
          onClicked: root.applyDraft()
        }

        Button {
          width: parent.width
          text: "Use system monospace"
          fontFamily: Style.font.menuFamily
          foreground: Color.menu.text
          bordered: true
          onClicked: root.resetToMono()
        }
      }
    }
  }
}
