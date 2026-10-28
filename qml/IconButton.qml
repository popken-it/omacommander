import QtQuick
import qs.Commons
import qs.Commons as Commons

// A Nautilus-style flat toolbar button drawn with a text glyph, so it works
// with every Omarchy theme and never depends on an icon theme being present.
Item {
  id: root

  property string glyph: ""
  property bool active: false
  property bool retro: false
  property color ink: retro ? "#c0c0c0" : Commons.Color.popups.text
  property color accent: retro ? "#ffff55" : Commons.Color.accent

  signal clicked()

  implicitWidth: Style.space(30)
  implicitHeight: Style.space(30)
  opacity: enabled ? 1 : 0.35

  Rectangle {
    anchors.fill: parent
    radius: Style.space(6)
    color: (mouse.containsMouse || root.active)
           ? Util.alpha(root.active ? root.accent : root.ink, root.active ? 0.18 : 0.10)
           : "transparent"
  }

  Text {
    anchors.centerIn: parent
    text: root.glyph
    textFormat: Text.PlainText
    color: root.active ? root.accent : root.ink
    font.family: "sans-serif"
    font.pixelSize: Style.font.title
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}
