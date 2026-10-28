import QtQuick
import qs.Commons
import qs.Commons as Commons

Rectangle {
  id: root

  property string label: ""
  property bool primary: false
  property bool danger: false
  property real fontScale: 1.0
  property bool retro: false

  readonly property color ink: retro ? "#c0c0c0" : Commons.Color.popups.text
  readonly property color accent: retro ? "#ffff55" : Commons.Color.accent
  readonly property color dangerColor: retro ? "#ff5555" : Commons.Color.urgent
  readonly property color panelBg: retro ? "#0000a8" : Commons.Color.background

  signal clicked()

  implicitWidth: labelText.implicitWidth + Style.space(26)
  implicitHeight: Style.space(30)
  radius: Style.space(7)
  color: primary ? (danger ? dangerColor : accent)
                  : (danger ? Util.alpha(dangerColor, 0.16)
                            : (mouse.containsMouse ? Util.alpha(ink, 0.10) : "transparent"))
  border.width: primary ? 0 : 1
  border.color: danger ? Util.alpha(dangerColor, 0.55) : Util.alpha(ink, 0.25)

  Text {
    id: labelText
    anchors.centerIn: parent
    text: root.label
    textFormat: Text.PlainText
    color: root.primary ? (root.danger ? root.ink : root.panelBg)
                        : (root.danger ? root.dangerColor : root.ink)
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
