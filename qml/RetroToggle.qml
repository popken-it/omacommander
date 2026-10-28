import QtQuick
import qs.Commons

Item {
  id: root

  property bool checked: false
  property string label: "Retro"
  property real fontScale: 1.0
  property string fontFamily: "sans-serif"
  property bool ultraRetro: false
  property bool checkbox: false
  property color ink: "#cacccc"
  property color accent: "#cacccc"
  property color panelBg: "#101315"

  signal toggled()

  implicitWidth: Style.space(68)
  implicitHeight: Style.space(24)
  opacity: enabled ? 1 : 0.35

  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    color: root.ink
    font.family: root.fontFamily
    font.pixelSize: root.ultraRetro ? 16 : Math.max(1, Math.round(Style.font.caption * root.fontScale))
  }

  Rectangle {
    id: track
    visible: !root.checkbox
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(28)
    height: Style.space(14)
    radius: root.ultraRetro ? 0 : height / 2
    color: root.checked ? root.accent : Util.alpha(root.ink, 0.18)
    border.width: 1
    border.color: Util.alpha(root.ink, 0.35)
  }

  Rectangle {
    visible: !root.checkbox
    width: Style.space(10)
    height: Style.space(10)
    radius: root.ultraRetro ? 0 : width / 2
    anchors.verticalCenter: track.verticalCenter
    x: root.checked ? track.x + track.width - width - Style.space(2)
                    : track.x + Style.space(2)
    color: root.checked ? root.panelBg : root.ink
  }

  Rectangle {
    id: checkboxBox
    visible: root.checkbox
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(16)
    height: Style.space(16)
    radius: root.ultraRetro ? 0 : Style.space(2)
    color: "transparent"
    border.width: 1
    border.color: root.ink

    Text {
      anchors.centerIn: parent
      visible: root.checked
      text: root.ultraRetro ? "√" : "✓"
      textFormat: Text.PlainText
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: root.ultraRetro ? 16 : Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.toggled()
  }
}
