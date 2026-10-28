import QtQuick
Item {
  property bool shown: false
  default property alias content: inner.data
  Item { id: inner; anchors.fill: parent }
}
