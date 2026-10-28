pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#ffffff"
  property color background: "#000000"
  property color accent: "#888888"
  property color urgent: "#ff0000"
  property Popups popups: Popups {}
  property Menu menu: Menu {}
}
