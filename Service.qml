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

  property var config: ({ enabled: false, family: "monospace", weight: "regular" })
  property bool ready: false
  property bool applying: false

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

  function applyStyle() {
    // Use the real family name. Never replace Quickshell's "monospace"
    // alias — bar icons need the Nerd Font fallback on that alias.
    Style.fontFamily = (root.config.enabled && root.config.family)
      ? root.config.family
      : "monospace"
  }

  function saveConfig(next, restartIfNeeded) {
    root.config = mergeConfig(next)
    writeProc.restartWhenDone = restartIfNeeded === true
    writeProc.running = false
    writeProc.command = ["/usr/bin/python3", root.configTool, "write"]
    writeProc.running = true
  }

  function clearRemap() {
    if (resetProc.running) resetProc.running = false
    resetProc.command = ["/usr/bin/bash", "-c", "exec >/dev/null 2>/dev/null; exec \"$0\" --reset", root.applyScript]
    resetProc.running = true
  }

  Process {
    id: readProc
    command: ["/usr/bin/python3", root.configTool]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var raw = String(text || "")
          if (raw.length > 512) raw = raw.slice(0, 512)
          root.config = root.mergeConfig(raw.trim() ? JSON.parse(raw.trim()) : {})
        } catch (e) {
          root.config = root.defaultConfig()
        }
        root.ready = true
        root.applyStyle()
        root.clearRemap()
      }
    }
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
    onStarted: writeProc.write(JSON.stringify(root.config) + "\n")
    onExited: function(code) {
      root.applying = false
      if (code !== 0) {
        console.warn("skuthus.shell-font: config write failed")
        return
      }
      root.applyStyle()
      root.clearRemap()
      if (writeProc.restartWhenDone)
        Quickshell.execDetached(["omarchy", "restart", "shell"])
    }
  }

  Process {
    id: resetProc
  }

  Component.onCompleted: root.applying = false
}
