import QtQuick
Item {
  property string path: ""
  property bool blockLoading: false
  property bool blockAllReads: false
  property bool printErrors: true
  property bool loaded: true
  property string content: ""
  function text(): string { return content }
}
