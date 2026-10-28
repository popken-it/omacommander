import QtQuick

// Test stub for Quickshell's PanelWindow. The real type is a layer-shell
// window with its own anchors group; tests only need its content, and the
// anchor lines are dropped by scripts/check.
Item {
  anchors.fill: parent
  property color color: "transparent"
  property int exclusionMode: 0

  default property alias content: inner.data

  Item {
    id: inner
    anchors.fill: parent
  }
}
