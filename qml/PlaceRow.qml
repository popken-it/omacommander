import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// One sidebar row: Places, a saved place, or a mounted device.
Item {
  id: root

  property string label: ""
  property string icon: "folder"
  property bool current: false
  property bool removable: false
  property real fontScale: 1.0
  property bool retro: false
  property bool ultraRetro: false
  property string fontFamily: "sans-serif"

  readonly property color ink: retro ? "#c0c0c0" : Commons.Color.popups.text
  readonly property color accent: retro ? "#ffff55" : Commons.Color.accent
  readonly property color hoverBg: retro ? "#3300aaaa" : Util.alpha(Commons.Color.popups.text, 0.07)
  readonly property color selectedBg: ultraRetro ? "#00aaaa" : (retro ? "#005f5f" : Util.alpha(Commons.Color.accent, 0.18))
  readonly property color selectedInk: ultraRetro ? "#000000" : accent

  signal clicked()
  signal removeClicked()

  height: ultraRetro ? 20 : Style.space(30)

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: 1
    anchors.bottomMargin: 1
    radius: root.ultraRetro ? 0 : Style.space(6)
    color: root.current ? root.selectedBg
                        : (rowMouse.containsMouse ? root.hoverBg : "transparent")
  }

  Image {
    x: Style.space(4)
    visible: !root.ultraRetro
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(16)
    height: Style.space(16)
    source: Quickshell.iconPath(root.icon, true)
    fillMode: Image.PreserveAspectFit
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: root.ultraRetro ? Style.space(4) : Style.space(32)
    anchors.right: parent.right
    anchors.rightMargin: root.removable ? Style.space(26) : Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.current ? root.selectedInk : root.ink
    font.family: root.fontFamily
    font.pixelSize: root.ultraRetro ? 16 : Math.max(1, Math.round(Style.font.body * root.fontScale))
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    visible: root.removable && (rowMouse.containsMouse || root.current)
    text: "✕"
    color: Util.alpha(root.ink, 0.55)
    font.family: root.fontFamily
    font.pixelSize: root.ultraRetro ? 16 : Math.max(1, Math.round(Style.font.caption * root.fontScale))

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      cursorShape: Qt.PointingHandCursor
      onClicked: root.removeClicked()
    }
  }
}
