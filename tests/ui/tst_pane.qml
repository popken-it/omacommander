import QtQuick
import QtTest
import "../../qml"

TestCase {
  name: "PaneNavigation"

  Pane { id: pane }

  function entry(name, path, dir) {
    return {
      name: name, path: path, dir: dir, link: false, hidden: false,
      size: 1, mtime: 1700000000,
      kind: dir ? "folder" : "document", parentLabel: ""
    }
  }

  function test_childToward() {
    compare(pane.childToward("/a", "/a/b"), "/a/b")
    compare(pane.childToward("/a", "/a/b/c"), "/a/b")
    compare(pane.childToward("/", "/a/b"), "/a")
    compare(pane.childToward("/a", "/x"), "")
    compare(pane.childToward("/a", "/a"), "")
  }

  function test_history_is_capped() {
    for (var i = 0; i < 130; i++) pane.navigate("/tmp/history-" + i)
    compare(pane.history.length, pane.historyLimit)
    compare(pane.history[pane.history.length - 1], "/tmp/history-129")
  }

  function test_reveal_selects_the_child_folder() {
    pane.navigate("/tmp")
    pane.reqId = 42
    pane.revealPath = "/tmp/Documents"
    pane.receive({
      id: 42, path: "/tmp", displayPath: "/tmp", parent: "/", free: 1,
      trash: false, writable: true, error: null, truncated: false,
      entries: [entry("aaa", "/tmp/aaa", true),
                entry("Documents", "/tmp/Documents", true)]
    })
    compare(pane.cursorEntry().path, "/tmp/Documents")
    verify(pane.isSelected("/tmp/Documents"))
  }

  function test_listing_always_selects_something() {
    pane.navigate("/tmp")
    pane.reqId = 43
    pane.receive({
      id: 43, path: "/tmp", displayPath: "/tmp", parent: "/", free: 1,
      trash: false, writable: true, error: null, truncated: false,
      entries: [entry("one", "/tmp/one", false),
                entry("two", "/tmp/two", false)]
    })
    compare(pane.selectedCount, 1)
    compare(pane.cursorEntry().path, "/tmp/one")
  }
}
