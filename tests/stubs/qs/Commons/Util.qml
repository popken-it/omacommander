pragma Singleton
import QtQuick
QtObject {
  function alpha(c: color, opacity: real): color { return c }
  function fileUrl(path: string): string { return "file://" + path }
  function execArgv(argv: var): void {}
}
