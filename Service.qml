import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/skuthus.shell-font"
  readonly property string applyScript: pluginDir + "/apply-font.sh"
  readonly property string configTool: pluginDir + "/read-config.py"
  readonly property string facePath: home + "/.local/share/fonts/omarchy-shell-font/OmarchyShellFont.ttf"
  readonly property string privateFamily: "OmarchyShellFont"
  readonly property int statusLimit: 200

  property var config: ({ enabled: false, family: "monospace", weight: "regular" })
  property bool ready: false
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
      next.family = raw.family.trim().slice(0, 128)
    if (typeof raw.weight === "string" && raw.weight.trim().length > 0)
      next.weight = raw.weight.trim().slice(0, 32)
    return next
  }

  function clipStatus(value) {
    var s = String(value || "").replace(/\s+/g, " ").trim()
    if (s.length > root.statusLimit) s = s.slice(s.length - root.statusLimit)
    return s
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

  function loadConfig() {
    if (!readProc.running) readProc.running = true
  }

  function saveConfig(next, restartIfNeeded) {
    root.config = mergeConfig(next)
    writeProc.restartWhenDone = restartIfNeeded !== false
    writeProc.running = false
    writeProc.command = ["/usr/bin/python3", root.configTool, "write"]
    writeProc.running = true
  }

  function runApply(restartWhenDone) {
    if (applyProc.running) applyProc.running = false
    root.applying = true
    applyProc.restartWhenDone = restartWhenDone === true
    if (root.config.enabled && root.config.family)
      applyProc.command = ["/usr/bin/bash", root.applyScript, root.config.family, root.config.weight]
    else
      applyProc.command = ["/usr/bin/bash", root.applyScript, "--reset"]
    applyProc.running = true
  }

  Process {
    id: readProc
    command: ["/usr/bin/python3", root.configTool]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var raw = String(text || "").trim()
          if (raw.length > 2048) raw = raw.slice(0, 2048)
          root.config = root.mergeConfig(raw ? JSON.parse(raw) : {})
        } catch (e) {
          console.warn("skuthus.shell-font: bad config")
          root.config = root.defaultConfig()
        }
        root.ready = true
        root.faceEpoch = Date.now()
        root.applyStyle()
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root.config = root.defaultConfig()
        root.ready = true
        root.applyStyle()
      }
    }
  }

  Process {
    id: writeProc
    property bool restartWhenDone: false
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: writeProc.write(JSON.stringify(root.config) + "\n")
    onExited: function(code) {
      if (code !== 0) {
        console.warn("skuthus.shell-font: config write failed")
        return
      }
      root.runApply(writeProc.restartWhenDone)
    }
  }

  Process {
    id: applyProc
    property bool restartWhenDone: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = root.clipStatus(text)
        if (out.length) root.lastStatus = out
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = root.clipStatus(text)
        if (err.length) root.lastStatus = err
      }
    }
    onExited: function(code) {
      root.applying = false
      if (code !== 0) {
        console.warn("skuthus.shell-font: apply failed")
        return
      }
      root.faceEpoch = Date.now()
      root.applyStyle()
      if (applyProc.restartWhenDone)
        Quickshell.execDetached(["omarchy", "restart", "shell"])
    }
  }

  Component.onCompleted: root.loadConfig()
}
