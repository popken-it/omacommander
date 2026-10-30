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

  function test_open_and_close_toggle_the_window() {
    files.open("{}")
    verify(files.opened)
    files.close()
    verify(!files.opened)
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

  function test_boomer_pane_gutter() {
    files.retro = true
    files.ultraRetro = true
    var a = findItem(files, "paneA")
    var b = findItem(files, "paneB")
    var contentWidth = a.parent.width
    verify(files.paneInset > 0)
    compare(a.x, files.paneInset)
    compare(b.x, a.x + a.width + files.paneGap)
    verify(Math.abs(b.width - a.width) <= 1)
    compare(b.x + b.width + files.paneInset, contentWidth)
    files.retro = false
  }

  function test_version_label_matches_manifest() {
    files.manifest = { id: "test", version: "9.9.9" }
    var label = findItem(files, "versionLabel")
    verify(label)
    compare(label.text, "v9.9.9")
    files.manifest = null
  }

  function test_job_progress_box_state() {
    files.job = { running: true, action: "copy", current: "a", done: 1, total: 4,
                  bytesDone: 25, bytesTotal: 100, speed: 10, dest: "/tmp" }
    verify(files.jobVisible())
    compare(files.jobFraction(), 0.25)
    compare(files.jobCount(), "1 of 4")
    compare(files.jobDetail(), "25 B of 100 B  ·  10 B/s  ·  8 s left")
    files.job = { running: true, action: "rename" }
    verify(!files.jobVisible())
    files.job = ({})
    verify(!files.jobVisible())
  }

  function test_operation_dialogs_default_to_ok() {
    files.openTransfer(true, ["/tmp/a"], "/tmp/dest", false)
    compare(files.dialog, "transfer")
    compare(files.pendingAction, "move")
    compare(files.dialogActions[0].label, "Cancel")
    compare(files.dialogActions[1].label, "OK")
    verify(files.dialogActions[1].primary)
    files.closeDialog()

    files.confirmEmptyTrash()
    compare(files.dialog, "confirm")
    compare(files.dialogActions[0].label, "Cancel")
    compare(files.dialogActions[1].label, "OK")
    verify(files.dialogActions[1].primary)
    files.closeDialog()

    files.openInput("rename", "Rename", "old.txt", "OK")
    compare(files.dialogActions[0].label, "Cancel")
    compare(files.dialogActions[1].label, "OK")
    files.closeDialog()
  }

  function test_mkdir_opens_the_new_folder() {
    var pane = findItem(files, "paneA")
    var service = findItem(files, "backend")
    pane.path = "/tmp"
    files.activePane = 0
    files.mkdirTarget = "/tmp/New Folder"
    files.mkdirPane = 0
    service.jobEvent({ event: "job", state: "done", action: "mkdir",
                       ok: true, message: "Folder created" })
    compare(pane.path, "/tmp/New Folder")
    compare(files.mkdirTarget, "")
  }

  function test_retro_palette() {
    files.retro = true
    compare(String(files.panelBg), "#0000a8")
    compare(String(files.ink), "#c0c0c0")
    compare(String(files.accent), "#ffff55")
    files.retro = false
  }
}
