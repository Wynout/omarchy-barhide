import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar Hide's picker: a bar button that opens the screen-selection panel, and
// the whole screen-selection mechanism.
//
// Each connected screen builds its own picker instance inside that screen's
// bar panel. An instance whose screen is not selected parks its own host
// panel — negative margin past the active edge plus ExclusionMode.Ignore,
// the same mechanism the native bar-hidden toggle uses — so the bar stays
// alive off-screen and can return without rebuilding its scene graph.
//
// Structurally the built-in clock: this entry point owns the bar slot and
// forwards the panel lifecycle, Panel.qml owns the popup content.
BarWidget {
  id: root
  moduleName: "wynout.barhide"

  Component.onCompleted: root.refreshSelection()

  Connections {
    target: Quickshell
    function onScreensChanged() {
      Qt.callLater(root.refreshSelection)
    }
  }

  // ---- Panel lifecycle. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    // The popup reads the park-authoritative selection, not the injected
    // `settings`: the module injection order made `settings` arrive late and
    // the rows would all render as "hide". Bind, so every refreshSelection()
    // rewrite reaches the popup without re-injection.
    if ("selectedRefs" in target)
      target.selectedRefs = Qt.binding(function() { return root.selectedRefs })
    if ("targetScreens" in target)
      target.targetScreens = Qt.binding(function() { return root.targetScreens })
  }

  // The picker mirrors the settings it writes: applied locally first so the
  // row badges move on the click itself, then persisted through
  // updateEntryInline — the widget-shell path for writing a widget's own
  // layout entry, the same write the built-in clock uses for its format
  // cycling. The shell.json write reloads the bar config in place and every
  // picker instance re-evaluates its park state.
  function applySettings(next) {
    var entry = { id: root.moduleName }
    for (var key in next)
      if (key !== "id") entry[key] = next[key]
    root.settings = entry
    if (!root.bar || !root.bar.shell
        || typeof root.bar.shell.updateEntryInline !== "function") return
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Settings -------------------------------------------------------------

  // The live shell config is this widget's authoritative settings source:
  // the injected `settings` property races the module injection order and
  // was observed to apply late, so parking resolves against the file itself.
  // Resolution order: 1. `bar.barhide` hand-edit override, 2. this widget's
  // own bar.layout entry, 3. the injected `settings` ((panel UI only)).
  property var barHideOverride: null
  property var ownEntryFromConfig: null

  function refsOf(obj) {
    if (!Util.isPlainObject(obj)) return null
    if (Array.isArray(obj.monitors)) return obj.monitors
    var legacy = []
    if (obj.primary) legacy.push(obj.primary)
    if (obj.secondary) legacy.push(obj.secondary)
    return legacy.length ? legacy : null
  }

  FileView {
    id: shellConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyShellConfig(text())
    onLoadFailed: root.applyShellConfig("")
    onFileChanged: reload()
  }

  function applyShellConfig(text) {
    var override = null
    var own = null
    try {
      var cfg = JSON.parse(String(text || "{}"))
      if (Util.isPlainObject(cfg.bar) && Util.isPlainObject(cfg.bar.barhide))
        override = cfg.bar.barhide
      var ownId = root.moduleName
      var sections = ["left", "center", "right"]
      var layout = Util.isPlainObject(cfg.bar) && Util.isPlainObject(cfg.bar.layout)
        ? cfg.bar.layout : {}
      for (var s = 0; s < sections.length && own === null; s++) {
        var arr = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
        for (var i = 0; i < arr.length; i++) {
          var entry = arr[i]
          if (Util.isPlainObject(entry) && String(entry.id || "") === ownId) {
            var ownFound = {}
            for (var k in entry)
              if (k !== "id") ownFound[k] = entry[k]
            own = ownFound
            break
          }
        }
      }
    } catch (e) {
      // A partially written shell.json reads as "nothing here"; the next
      // file change re-applies.
    }
    root.barHideOverride = override
    root.ownEntryFromConfig = own
    Qt.callLater(root.refreshSelection)
  }

  // The screens selected to carry the bar.
  property var selectedRefs: []
  property var targetScreens: []

  // Re-resolves from the config file (and, before it is loaded, from the
  // injected `settings`). Every trigger calls this and rewrites both props.
  function refreshSelection() {
    var list = refsOf(root.barHideOverride)
      || refsOf(root.ownEntryFromConfig)
      || refsOf(settings)
      || []
    root.selectedRefs = list

    // The connected subset of the selected monitors, deduped by name. An
    // empty list means "the native behavior: every screen".
    var out = []
    var seen = {}
    var screens = Quickshell.screens || []
    for (var i = 0; i < list.length; i++) {
      var s2 = Model.findScreen(screens, list[i])
      if (s2 && seen[s2.name] !== true) {
        seen[s2.name] = true
        out.push(s2)
      }
    }
    root.targetScreens = out
  }

  readonly property bool hasTarget: selectedRefs.length > 0

  function shouldShow(screen) {
    if (root.targetScreens.length === 0) return true
    for (var i = 0; i < root.targetScreens.length; i++)
      if (root.targetScreens[i] === screen
          || (screen && root.targetScreens[i].name === screen.name)) return true
    return false
  }

  // ---- Global bar-hidden flag ------------------------------------------------

  // Same probe the native bar uses: the flag file's presence is the bar-off
  // state, and the directory watcher re-runs the probe because FileView
  // cannot watch a file that does not exist yet.
  property bool barHidden: false

  Process {
    id: barHiddenProbe

    running: true
    command: ["bash", "-c",
      "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) { root.barHidden = String(line).trim() === "yes" }
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // ---- Self-parking ------------------------------------------------------------

  // This widget instance lives inside its own screen's bar panel; the
  // attached QsWindow is that panel. Every instance parks only its own host,
  // so there is no cross-window coordination and no reliance on the native
  // bar's object tree.
  readonly property var hostWindow: QsWindow.window
  readonly property var hostScreen: hostWindow ? hostWindow.screen : null
  readonly property bool parked: root.barHidden || !root.shouldShow(root.hostScreen)
  readonly property real parkedOffset: root.parked
    ? -Math.max(root.bar && root.bar.barSize > 0 ? root.bar.barSize : 26, 26)
    : 0

  Binding {
    target: root.hostWindow
    property: "exclusionMode"
    value: root.parked ? ExclusionMode.Ignore : ExclusionMode.Auto
    when: root.hostWindow !== null && "exclusionMode" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.top"
    value: root.bar && root.bar.position === "top" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.bottom"
    value: root.bar && root.bar.position === "bottom" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.left"
    value: root.bar && root.bar.position === "left" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.right"
    value: root.bar && root.bar.position === "right" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  // ---- Bar slot ----------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    root.refreshSelection()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font glyph as UTF-16 escapes (U+F0DDC md-monitor-star — the
    // pinned monitor) — literal astral-plane characters get mangled by
    // some toolchains, escapes keep the source pure ASCII.
    text: "\uDB83\uDDDC"
    // targets may be one or several screens; "single" is just "a selection"
    tooltipText: root.hasTarget
      ? "Bar Hide: bar on " + root.targetScreens.length + " of "
        + (Quickshell.screens || []).length + " screens"
      : "Bar Hide: bar on every screen"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
    }
  }
}
