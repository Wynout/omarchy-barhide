// Catalog of selectable picker glyphs. Nerd Font Material Design
// codepoints, stored as UTF-16 surrogate escapes so this file stays pure
// ASCII (some toolchains mangle literal astral-plane source characters).
// Codepoints verified against nerd-fonts v3.5.1 glyphnames.json.
pragma Singleton
import QtQuick

QtObject {
  // f0ddc md-monitor-star — the current default picker icon
  readonly property string monitorStar: "\uDB83\uDDDC"
  // f0379 md-monitor
  readonly property string monitor: "\uDB80\uDFB9"
  // f037a md-monitor-multiple
  readonly property string monitorMultiple: "\uDB80\uDFBA"
  // f1104 md-monitor-shimmer
  readonly property string monitorShimmer: "\uDB84\uDD04"
  // f0aab md-desktop-tower-monitor
  readonly property string desktopTowerMonitor: "\uDB82\uDEAB"

  // Offered on the options page, in display order.
  readonly property var choices: [
    { glyph: monitorStar, name: "monitor star" },
    { glyph: monitor, name: "monitor" },
    { glyph: monitorMultiple, name: "monitors" },
    { glyph: monitorShimmer, name: "shimmer" },
    { glyph: desktopTowerMonitor, name: "tower" }
  ]
}
