pragma Singleton
import QtQuick
QtObject {
  function iconPath(name: string, check: bool): string { return "" }
  function env(name: string): string { return "" }
  function execDetached(argv: var): void {}
}
