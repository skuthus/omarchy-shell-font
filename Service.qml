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
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string applyScript: pluginDir + "/apply-font.sh"
  readonly property string privateFamily: "OmarchyShellFont"

  property var config: ({ enabled: false, family: "monospace", weight: "regular" })
  property bool ready: false
  property bool applyQueued: false
  property bool restartAfterApply: false
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

  function qtHasFamily(name) {
    var families = Qt.fontFamilies() || []
    for (var i = 0; i < families.length; i++) {
      if (String(families[i]) === name) return true
    }
    return false
  }

  function applyStyle() {
    if (!root.config.enabled) {
      Style.fontFamily = "monospace"
      return
    }
    if (root.config.weight === "regular") {
      Style.fontFamily = root.config.family
      return
    }
    Style.fontFamily = root.privateFamily
  }

  function saveConfig(next, restartIfNeeded) {
    root.config = mergeConfig(next)
    var json = JSON.stringify(root.config, null, 2) + "\n"
    if (typeof configFile.setText === "function") configFile.setText(json)
    queueApply(restartIfNeeded !== false)
  }

  function queueApply(restartIfNeeded) {
    root.restartAfterApply = restartIfNeeded === true
    if (applyProc.running) {
      root.applyQueued = true
      return
    }
    runApply()
  }

  function runApply() {
    if (root.config.enabled && root.config.family)
      applyProc.command = ["bash", root.applyScript, root.config.family, root.config.weight]
    else
      applyProc.command = ["bash", root.applyScript, "--reset"]
    applyProc.running = true
  }

  function maybeRestart() {
    if (!root.restartAfterApply) return
    if (!root.config.enabled) return
    if (root.config.weight === "regular") return
    // Qt caches faces; a new weight only paints after the shell restarts.
    Quickshell.execDetached(["omarchy", "restart", "shell"])
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onLoaded: {
      var raw = typeof configFile.text === "function" ? configFile.text() : configFile.text
      try {
        root.config = root.mergeConfig(raw && String(raw).trim() ? JSON.parse(String(raw)) : {})
      } catch (e) {
        console.warn("skuthus.shell-font: bad config", e)
        root.config = root.defaultConfig()
      }
      root.ready = true
      root.queueApply(false)
    }

    onLoadFailed: {
      root.config = root.defaultConfig()
      root.ready = true
    }

    onFileChanged: configFile.reload()
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastStatus = String(text || "").trim()
    }
    onExited: function(code) {
      if (code === 0) root.applyStyle()
      else console.warn("skuthus.shell-font: apply failed:", root.lastStatus)
      if (root.applyQueued) {
        root.applyQueued = false
        root.runApply()
        return
      }
      if (code === 0) root.maybeRestart()
    }
  }
}
