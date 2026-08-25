import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "skuthus.shell-font"

  function toggleOverlay() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle("skuthus.shell-font")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "Aa"
    tooltipText: "Shell font"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggleOverlay()
    }
  }
}
