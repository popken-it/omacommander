import QtQuick
import qs.Commons
import qs.Commons as Commons

Rectangle {
  id: root

  property string label: ""
  property bool primary: false
  property bool danger: false
  property real fontScale: 1.0

  signal clicked()

  implicitWidth: labelText.implicitWidth + Style.space(26)
  implicitHeight: Style.space(30)
  radius: Style.space(7)
  color: primary ? Commons.Color.accent
                  : (danger ? Util.alpha(Commons.Color.urgent, 0.16)
                            : (mouse.containsMouse ? Util.alpha(Commons.Color.popups.text, 0.10) : "transparent"))
  border.width: primary ? 0 : 1
  border.color: danger ? Util.alpha(Commons.Color.urgent, 0.55) : Util.alpha(Commons.Color.popups.text, 0.25)

  Text {
    id: labelText
    anchors.centerIn: parent
    text: root.label
    textFormat: Text.PlainText
    color: root.primary ? Commons.Color.background
                        : (root.danger ? Commons.Color.urgent : Commons.Color.popups.text)
    font.family: "sans-serif"
    font.pixelSize: Math.max(1, Math.round(Style.font.body * root.fontScale))
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
