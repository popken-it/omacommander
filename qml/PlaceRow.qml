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

  signal clicked()
  signal removeClicked()

  height: Style.space(30)

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: 1
    anchors.bottomMargin: 1
    radius: Style.space(6)
    color: root.current ? Util.alpha(Commons.Color.accent, 0.18)
                        : (rowMouse.containsMouse ? Util.alpha(Commons.Color.popups.text, 0.07) : "transparent")
  }

  Image {
    x: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(16)
    height: Style.space(16)
    source: Quickshell.iconPath(root.icon, true)
    fillMode: Image.PreserveAspectFit
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(32)
    anchors.right: parent.right
    anchors.rightMargin: root.removable ? Style.space(26) : Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.current ? Commons.Color.accent : Commons.Color.popups.text
    font.family: "sans-serif"
    font.pixelSize: Math.max(1, Math.round(Style.font.body * root.fontScale))
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
    color: Util.alpha(Commons.Color.popups.text, 0.55)
    font.family: "sans-serif"
    font.pixelSize: Math.max(1, Math.round(Style.font.caption * root.fontScale))

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      cursorShape: Qt.PointingHandCursor
      onClicked: root.removeClicked()
    }
  }
}
