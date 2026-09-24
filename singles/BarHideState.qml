pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../Model.js" as Model

// Bar Hide's shared state: one copy per shell engine, used by every picker
// instance on every screen.
//
// Before v0.4.1 each picker instance owned its own shell.json FileView, its
// own bar-off probe, and its own toggles-dir watcher. The bar-off directory
// watch can permanently stop delivering events after flag changes land in
// quick succession (the native bar needed an IPC nudge for exactly that,
// see plugins/bar/Bar.qml), and N independent watchers can strand N screens
// independently — the screens would then disagree about park state. Here the
// watchers exist once and every panel reads the same resolved selection.
//
// The root is an Item (not QtObject): a singleton must offer a children
// property for its FileView/Process/Timer; a plain QtObject cannot hold
// children.
Item {
  id: st

  readonly property string moduleName: "wynout.barhide"

  // True once the live shell config has been read at least once (or read as
  // definitively absent). Parking decisions are gated on this so startup
  // never parks from stale fallback data: until the file speaks, the native
  // "bar on every screen" behavior applies, matching what the user sees at
  // that moment with no Bar Hide active.
  property bool configReady: false

  // The `bar.barhide` hand-edit override and the widget's own bar.layout
  // entry from the last good parse. A transient partial parse (mid-write
  // shell.json) keeps the previous values instead of pretending the keys
  // vanished; the next file change re-parses.
  property var overrideEntry: null
  property var ownEntryFromConfig: null

  // The screens selected to carry the bar (raw refs), and the connected
  // subset, deduped by output name. Empty targetScreens with configReady
  // means "the native behavior: every screen".
  property var selectedRefs: []
  property var targetScreens: []
  readonly property bool hasSelection: selectedRefs.length > 0

  // Local echo of a selection the picker just applied through its UI; the
  // pending shell.json write confirms it (and updates every other instance
  // through the same file watcher).
  function previewEntry(entry) {
    st.ownEntryFromConfig = entry
    st.refreshSelection()
  }

  // ---- Settings -------------------------------------------------------------

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
    onLoaded: st.applyShellConfig(text())
    onLoadFailed: st.applyShellConfig("")
    onFileChanged: reload()
  }

  function applyShellConfig(text) {
    var override = null
    var own = null
    try {
      var cfg = JSON.parse(String(text || "{}"))
      if (Util.isPlainObject(cfg.bar) && Util.isPlainObject(cfg.bar.barhide))
        override = cfg.bar.barhide
      var sections = ["left", "center", "right"]
      var layout = Util.isPlainObject(cfg.bar) && Util.isPlainObject(cfg.bar.layout)
        ? cfg.bar.layout : {}
      for (var s = 0; s < sections.length && own === null; s++) {
        var arr = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
        for (var i = 0; i < arr.length; i++) {
          var entry = arr[i]
          if (Util.isPlainObject(entry) && String(entry.id || "") === st.moduleName) {
            var ownFound = {}
            for (var k in entry)
              if (k !== "id") ownFound[k] = entry[k]
            own = ownFound
            break
          }
        }
      }
      // Only a fully parsed file updates state; the parse-error path leaves
      // the previous values (and refreshes nothing).
      st.overrideEntry = override
      st.ownEntryFromConfig = own
      st.configReady = true
      st.refreshSelection()
    } catch (e) {
      // A partially written shell.json reads as nothing changed; the next
      // file change re-applies.
    }
  }

  function refreshSelection() {
    var list = refsOf(st.overrideEntry)
      || refsOf(st.ownEntryFromConfig)
      || []
    st.selectedRefs = list

    // The connected subset of the selected monitors, deduped by name. A
    // reference whose monitor is disconnected stays in the list (pend list
    // semantics: the bar returns with the monitor).
    var out = []
    var seen = {}
    var screens = Quickshell.screens || []
    for (var i = 0; i < list.length; i++) {
      var s = Model.findScreen(screens, list[i])
      if (s && seen[s.name] !== true) {
        seen[s.name] = true
        out.push(s)
      }
    }
    st.targetScreens = out
  }

  // The connected screens of this configuration, re-evaluated whenever they
  // appear, disappear, or change identity.
  Connections {
    target: Quickshell
    function onScreensChanged() { st.refreshSelection() }
  }

  // ---- Global bar-hidden flag ----------------------------------------------

  // Mirror of the on-disk `bar-off` flag: true while the global bar-hidden
  // toggle is active, in which case every panel parks regardless of selection.
  property bool barHidden: false

  // Same probe the native bar uses: the flag file's presence is the bar-off
  // state. The parent toggles directory is watched because FileView cannot
  // observe a file that does not exist yet.
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: st.syncBarHidden()
  }

  function syncBarHidden() {
    barHiddenProbe.running = true
    // The native bar documented this failure mode: a directory watch can
    // permanently stop delivering events after flag changes land in quick
    // succession. The periodic re-probe is the plugin's own belt-and-braces
    // version of the native bar's IPC nudge; it costs one bash invocation
    // every 15 seconds.
    reProbeTimer.restart()
  }

  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c",
      "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser {
      // Start rather than restart on the caller's side: a probe already in
      // flight was launched by the directory watch after the flag flipped,
      // so its answer is current.
      onRead: function(line) {
        var on = String(line).trim() === "yes"
        if (on !== st.barHidden) st.barHidden = on
      }
    }
  }

  Timer {
    id: reProbeTimer
    interval: 15000
    onTriggered: {
      // Re-probe the bar-off flag (watch-failure fallback), and re-read the
      // shell config: quickshell can drop an in-flight FileView operation
      // ("got operation finished from dropped operation" warnings), which
      // swallowed one shell.json write during testing — the watcher saw the
      // change but the reload was dropped. Re-reading on the same fallback
      // timer makes every missed write converge anyway.
      barHiddenProbe.running = true
      shellConfigFile.reload()
      shellParseRetryTimer.restart()
    }
  }

  // reload() is async; give it a beat, then make sure the parse actually
  // re-ran (onLoaded may not fire at all for a no-op reload).
  Timer {
    id: shellParseRetryTimer
    interval: 250
    onTriggered: _forceParse()
  }

  function _forceParse() {
    // applyShellConfig from current content; if FileView never delivered it,
    // this is the catch-up. Cheap: parse of a small JSON, at most every 15s.
    applyShellConfig(shellConfigFile.text())
  }
}
