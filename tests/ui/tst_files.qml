import QtQuick
import QtTest
import "../../qml"

TestCase {
  name: "OmaNCommanderState"

  Files { id: files }

  function test_defaults() {
    compare(files.fontScale, 1.2)
    verify(!files.retro)
  }

  function test_font_scale_limits_and_reset() {
    files.changeFontSize(1.0)
    compare(files.fontScale, 1.6)
    files.changeFontSize(-1.0)
    compare(files.fontScale, 0.8)
    files.fontScale = files.defaultFontScale
  }

  function findItem(item, name) {
    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      if (kids[i].objectName === name) return kids[i]
      var found = findItem(kids[i], name)
      if (found) return found
    }
    return null
  }

  function test_recover_moved_folder() {
    var pane = findItem(files, "paneA")
    pane.path = "/tmp/old/sub"
    files.recoverPanes(["/tmp/old"])
    compare(pane.path, "/tmp")
  }

  function test_setActive_switches_and_leaves_search() {
    files.searchActive = true
    files.setActive(1)
    compare(files.activePane, 1)
    verify(!files.searchActive)
    files.setActive(0)
    compare(files.activePane, 0)
  }

  function test_boomer_only_with_retro() {
    files.retro = true
    files.ultraRetro = true
    verify(files.ultraRetro)
    compare(files.viewMode, "list")
    verify(files.split)
    files.retro = false
    verify(!files.ultraRetro)
  }

  function test_retro_palette() {
    files.retro = true
    compare(String(files.panelBg), "#0000a8")
    compare(String(files.ink), "#c0c0c0")
    compare(String(files.accent), "#ffff55")
    files.retro = false
  }
}
