import QtQuick
import qs.Commons

Item {
  id: root

  property bool checked: false
  property color ink: "#cacccc"
  property color accent: "#cacccc"
  property color panelBg: "#101315"
  property real fontScale: 1.0

  signal toggled()

  implicitWidth: Style.space(68)
  implicitHeight: Style.space(24)

  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: "Retro"
    textFormat: Text.PlainText
    color: root.ink
    font.family: "sans-serif"
    font.pixelSize: Math.max(1, Math.round(Style.font.caption * root.fontScale))
  }

  Rectangle {
    id: track
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(28)
    height: Style.space(14)
    radius: height / 2
    color: root.checked ? root.accent : Util.alpha(root.ink, 0.18)
    border.width: 1
    border.color: Util.alpha(root.ink, 0.35)
  }

  Rectangle {
    width: Style.space(10)
    height: Style.space(10)
    radius: width / 2
    anchors.verticalCenter: track.verticalCenter
    x: root.checked ? track.x + track.width - width - Style.space(2)
                    : track.x + Style.space(2)
    color: root.checked ? root.panelBg : root.ink
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
