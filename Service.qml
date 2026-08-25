import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/shell-font.json"
  readonly property string applyScript: home + "/.config/omarchy/plugins/skuthus.shell-font/apply-font.sh"
  readonly property string privateFamily: "OmarchyShellFont"

  property var config: ({ enabled: false, family: "monospace", weight: "regular" })
  property bool ready: false
  property bool writingConfig: false
  property string lastStatus: ""

  function defaultConfig() {
    return { enabled: false, family: "monospace", weight: "regular" }
  }

  function mergeConfig(raw) {
    var next = defaultConfig()
    if (!raw || typeof raw !== "object") return next
    if (raw.enabled === true || raw.enabled === false) next.enabled = raw.enabled
    if (typeof raw.family === "string" && raw.family.trim().length > 0)
      next.family = raw.family.trim()
    if (typeof raw.weight === "string" && raw.weight.trim().length > 0)
      next.weight = raw.weight.trim().toLowerCase()
    return next
  }

  function applyStyle() {
    // Qt cannot load the synthetic OmarchyShellFont name from a font's
    // name table — it falls back to a symbol face and scrambles the UI.
    // Keep the QML family on the fontconfig alias; apply-font.sh remaps
    // quickshell's monospace request to the chosen face.
    Style.fontFamily = "monospace"
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function applyNow(restart) {
    var cmd
    if (root.config.enabled && root.config.family) {
      cmd = shellQuote(root.applyScript) + " " + shellQuote(root.config.family) + " " + shellQuote(root.config.weight)
    } else {
      cmd = shellQuote(root.applyScript) + " --reset"
    }
    if (restart) cmd += " && omarchy restart shell"
    applyStyle()
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function saveConfig(next, restartIfNeeded) {
    root.config = mergeConfig(next)
    root.writingConfig = true
    var json = JSON.stringify(root.config, null, 2) + "\n"
    if (typeof configFile.setText === "function") configFile.setText(json)
    applyNow(restartIfNeeded !== false)
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onLoaded: {
      if (root.writingConfig) {
        root.writingConfig = false
        return
      }
      var raw = typeof configFile.text === "function" ? configFile.text() : configFile.text
      try {
        root.config = root.mergeConfig(raw && String(raw).trim() ? JSON.parse(String(raw)) : {})
      } catch (e) {
        console.warn("skuthus.shell-font: bad config", e)
        root.config = root.defaultConfig()
      }
      root.ready = true
      root.applyNow(false)
    }

    onLoadFailed: {
      root.writingConfig = false
      root.config = root.defaultConfig()
      root.ready = true
    }

    onFileChanged: {
      if (root.writingConfig) return
      configFile.reload()
    }
  }
}
