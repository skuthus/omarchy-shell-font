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
  readonly property string facePath: home + "/.local/share/fonts/omarchy-shell-font/OmarchyShellFont.ttf"
  readonly property string privateFamily: "OmarchyShellFont"

  property var config: ({ enabled: false, family: "monospace", weight: "regular" })
  property bool ready: false
  property bool writingConfig: false
  property bool applying: false
  property string lastStatus: ""
  property int faceEpoch: 0

  FontLoader {
    id: faceLoader
    source: root.config.enabled && root.faceEpoch >= 0 ? ("file://" + root.facePath + "?v=" + root.faceEpoch) : ""
    onStatusChanged: {
      if (status === FontLoader.Ready && root.config.enabled && name)
        Style.fontFamily = name
    }
  }

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
    if (faceLoader.status === FontLoader.Ready && faceLoader.name)
      Style.fontFamily = faceLoader.name
    else
      Style.fontFamily = "monospace"
  }

  function runApply(restartWhenDone) {
    if (applyProc.running) {
      applyProc.running = false
    }
    root.applying = true
    applyProc.restartWhenDone = restartWhenDone === true
    if (root.config.enabled && root.config.family)
      applyProc.command = ["/usr/bin/bash", root.applyScript, root.config.family, root.config.weight]
    else
      applyProc.command = ["/usr/bin/bash", root.applyScript, "--reset"]
    applyProc.running = true
  }

  function saveConfig(next, restartIfNeeded) {
    root.config = mergeConfig(next)
    root.writingConfig = true
    var json = JSON.stringify(root.config, null, 2) + "\n"
    if (typeof configFile.setText === "function") configFile.setText(json)
    runApply(restartIfNeeded !== false)
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
      root.faceEpoch = Date.now()
      root.applyStyle()
    }

    onLoadFailed: {
      root.writingConfig = false
      root.config = root.defaultConfig()
      root.ready = true
      root.applyStyle()
    }

    onFileChanged: {
      if (root.writingConfig) return
      configFile.reload()
    }
  }

  Process {
    id: applyProc
    property bool restartWhenDone: false
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
      root.applying = false
      if (code !== 0) {
        console.warn("skuthus.shell-font: apply failed:", root.lastStatus)
        return
      }
      root.faceEpoch = Date.now()
      root.applyStyle()
      if (applyProc.restartWhenDone)
        Quickshell.execDetached(["omarchy", "restart", "shell"])
    }
  }
}
