pragma Singleton
import QtQuick
QtObject {
  property int cornerRadius: 0
  property int gapsOut: 5
  function space(px: real): int { return Math.round(px) }
  property FontTokens font: FontTokens {}
  property Spacing spacing: Spacing {}
}
