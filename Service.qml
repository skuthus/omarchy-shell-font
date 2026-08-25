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
  readonly property string pluginDir: home + "/.config/omarchy/plugins/skuthus.shell-font"
  readonly property string applyScript: pluginDir + "/apply-font.sh"
  readonly property string privateFamily: "OmarchyShellFont"

  property var config: ({ enabled: false, family: "monospace", weight: "regular" })
  property bool ready: false
  property bool applyQueued: false
  property bool restartAfterApply: false
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
    root.writingConfig = true
    var json = JSON.stringify(root.config, null, 2) + "\n"
    if (typeof configFile.setText === "function") configFile.setText(json)
    queueApply(restartIfNeeded !== false)
  }

  function queueApply(restartIfNeeded) {
    // A FileView reload must not cancel a user-requested restart.
    if (restartIfNeeded) root.restartAfterApply = true
    else if (!applyProc.running && !root.applyQueued) root.restartAfterApply = false
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
    root.restartAfterApply = false
    Quickshell.execDetached(["omarchy", "restart", "shell"])
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
      root.queueApply(false)
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

  Process {
    id: applyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out.length > 0) root.lastStatus = out
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err.length > 0) root.lastStatus = err
      }
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
