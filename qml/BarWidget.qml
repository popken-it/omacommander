// Bar icon that summons the Files overlay. The overlay is keepLoaded, so the
// shell's own toggle handles open/close without a service of our own.
import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "popkenr.files"

  readonly property bool iconFound: Quickshell.iconPath("folder", true) !== ""

  implicitWidth: Style.space(26)
  implicitHeight: barSize

  Image {
    anchors.centerIn: parent
    width: Style.space(16)
    height: Style.space(16)
    source: Quickshell.iconPath("folder", true)
    visible: root.iconFound
    fillMode: Image.PreserveAspectFit
  }

  Text {
    anchors.centerIn: parent
    visible: !root.iconFound
    text: "▤"
    textFormat: Text.PlainText
    color: root.bar ? root.bar.barForeground : Commons.Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.icon
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(
      ["omarchy-shell", "shell", "toggle", "popkenr.files", "{}"])
    onEntered: if (root.bar) root.bar.showTooltip(root, "Files")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
