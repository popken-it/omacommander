import QtQuick
Item {
  property bool running: false
  property var command: []
  property bool stdinEnabled: false
  property var stdout: null
  property var stderr: null
  signal started()
  signal exited(int code)
  function write(data: string): void {}
}
