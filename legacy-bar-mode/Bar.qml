import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import qs.plugins.bar as Native
import "Model.js" as Model

// MonoBar — shows the Omarchy bar on the selected screens only.
//
// Inherits the entire installed bar (widgets, layout, theming, popouts, IPC)
// the way topbar-peek does, and parks every bar panel that is not on a
// selected screen. Every selected monitor carries the bar while connected;
// when none of them is, the bar behaves exactly like the native bar: one
// panel per screen.
//
// Where the settings live:
//   1. `bar.monobar` in shell.json (hand-edit override), or
//   2. MonoBar's own entry in bar.layout (written by the picker widget).
// Monitors is an array of screen references — { name, model, serial }
// captured from the live screen when picked, or a plain string matched as a
// substring of the screen's model or name. The older primary/secondary keys
// are still read (mapped into the list) and rewritten in the new shape by
// the picker's next save.
Native.Bar {
  id: root

  // The native bar creates its per-screen panels through Variants children.
  // Find them once the component completes and again whenever the screen set
  // changes; our own park-controller Variants is skipped by identity.
  property var nativeVariants: []
  property int screensRevision: 0
  property bool pickerEnsured: false

  readonly property string ownId: manifest ? String(manifest.id || "") : ""

  // ---- Settings -----------------------------------------------------------

  readonly property var monobarEntry: {
    var cfg = barConfig
    if (Util.isPlainObject(cfg) && Util.isPlainObject(cfg.monobar)) return cfg.monobar
    if (ownId === "") return {}
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var layout = Util.isPlainObject(cfg) && Util.isPlainObject(cfg.layout) ? cfg.layout : {}
      var arr = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var i = 0; i < arr.length; i++) {
        var entry = arr[i]
        if (Util.isPlainObject(entry) && Util.canonicalWidgetId(String(entry.id || "")) === ownId) {
          var copy = {}
          for (var k in entry)
            if (k !== "id") copy[k] = entry[k]
          return copy
        }
      }
    }
    return {}
  }

  // The selected screens, as references. Reads the new `monitors` list and
  // falls back to the legacy primary/secondary pair so existing configs keep
  // working until the picker rewrites them.
  readonly property var selectedRefs: {
    if (!Util.isPlainObject(monobarEntry)) return []
    if (Array.isArray(monobarEntry.monitors)) return monobarEntry.monitors
    var legacy = []
    if (monobarEntry.primary) legacy.push(monobarEntry.primary)
    if (monobarEntry.secondary) legacy.push(monobarEntry.secondary)
    return legacy
  }
  readonly property bool autoInsertPicker: !Util.isPlainObject(monobarEntry) || monobarEntry.autoInsertPicker !== false

  // ---- Target screens -------------------------------------------------------

  // The connected subset of the selected monitors, deduped by name. An empty
  // list means "the native behavior: every screen".
  readonly property var targetScreens: {
    screensRevision
    var out = []
    var seen = {}
    var screens = Quickshell.screens || []
    for (var i = 0; i < selectedRefs.length; i++) {
      var s = Model.findScreen(screens, selectedRefs[i])
      if (s && seen[s.name] !== true) {
        seen[s.name] = true
        out.push(s)
      }
    }
    return out
  }

  function shouldShow(screen) {
    if (targetScreens.length === 0) return true
    for (var i = 0; i < targetScreens.length; i++)
      if (targetScreens[i] === screen || (screen && targetScreens[i].name === screen.name)) return true
    return false
  }

  // ---- Native panel discovery ---------------------------------------------

  function findNativeVariants() {
    var found = []
    for (var i = 0; i < root.data.length; i++) {
      var child = root.data[i]
      if (child === parkControllers) continue
      if (child && "instances" in child) found.push(child)
    }
    root.nativeVariants = found
  }

  readonly property var allPanels: {
    var out = []
    for (var i = 0; i < nativeVariants.length; i++) {
      var variants = nativeVariants[i]
      var instances = variants ? variants.instances : null
      if (!instances) continue
      for (var j = 0; j < instances.length; j++)
        if (instances[j]) out.push(instances[j])
    }
    return out
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.screensRevision++
      Qt.callLater(root.findNativeVariants)
    }
  }

  // ---- Parking -------------------------------------------------------------

  // One controller per native panel instance. Real panels park off the
  // active edge and release their exclusive zone — the same mechanism the
  // native bar-hidden toggle uses — while drag/move ghosts are hidden by
  // visibility so a drag can never drop the bar onto a screen that will not
  // show it.
  Variants {
    id: parkControllers

    model: root.allPanels

    delegate: Component {
      Item {
        id: park

        required property var modelData

        readonly property bool isGhost: "ghostScreen" in modelData
        readonly property var panelScreen: isGhost ? modelData.ghostScreen : modelData.screen
        readonly property bool parked: !root.shouldShow(panelScreen) || root.barHidden
        readonly property real parkedOffset: parked ? -Math.max(root.barSize || 26, 26) : 0

        Binding {
          target: park.modelData
          property: "visible"
          value: !park.parked
          when: park.isGhost
          restoreMode: Binding.RestoreBindingOrValue
        }

        Binding {
          target: park.modelData
          property: "exclusionMode"
          value: park.parked ? ExclusionMode.Ignore : ExclusionMode.Auto
          when: !park.isGhost
          restoreMode: Binding.RestoreBindingOrValue
        }

        Binding {
          target: park.modelData
          property: "margins.top"
          value: root.position === "top" ? park.parkedOffset : 0
          when: !park.isGhost
          restoreMode: Binding.RestoreBindingOrValue
        }

        Binding {
          target: park.modelData
          property: "margins.bottom"
          value: root.position === "bottom" ? park.parkedOffset : 0
          when: !park.isGhost
          restoreMode: Binding.RestoreBindingOrValue
        }

        Binding {
          target: park.modelData
          property: "margins.left"
          value: root.position === "left" ? park.parkedOffset : 0
          when: !park.isGhost
          restoreMode: Binding.RestoreBindingOrValue
        }

        Binding {
          target: park.modelData
          property: "margins.right"
          value: root.position === "right" ? park.parkedOffset : 0
          when: !park.isGhost
          restoreMode: Binding.RestoreBindingOrValue
        }
      }
    }
  }

  // ---- Picker onboarding ----------------------------------------------------

  // `omarchy plugin enable` makes MonoBar the bar but cannot also place the
  // picker widget, so the first activation inserts one picker entry at the
  // front of the right section. Opt out with bar.monobar.autoInsertPicker:
  // false in shell.json.
  function ensurePickerEntry() {
    if (root.pickerEnsured) return
    if (!root.autoInsertPicker) return
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    if (ownId === "") return
    root.pickerEnsured = true
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar) || !Util.isPlainObject(config.bar.layout)) return
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var arr = Array.isArray(config.bar.layout[sections[s]]) ? config.bar.layout[sections[s]] : []
        for (var i = 0; i < arr.length; i++)
          if (arr[i] && Util.canonicalWidgetId(String(arr[i].id || "")) === ownId) return
      }
      if (!Array.isArray(config.bar.layout.right)) config.bar.layout.right = []
      config.bar.layout.right.unshift({ id: ownId })
    })
  }

  onShellChanged: Qt.callLater(ensurePickerEntry)

  Component.onCompleted: {
    Qt.callLater(findNativeVariants)
    Qt.callLater(ensurePickerEntry)
  }

  // ---- Introspection ---------------------------------------------------------

  function applyEntry(entry) {
    if (!Util.isPlainObject(entry)) return
    if (ownId === "" || Util.canonicalWidgetId(String(entry.id || "")) !== ownId) return
    var clean = { id: ownId }
    for (var k in entry)
      if (k !== "id") clean[k] = entry[k]
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar) || !Util.isPlainObject(config.bar.layout)) return
      var sections = ["left", "center", "right"]
      var replaced = false
      for (var s = 0; s < sections.length; s++) {
        var arr = Array.isArray(config.bar.layout[sections[s]]) ? config.bar.layout[sections[s]] : []
        for (var i = 0; i < arr.length; i++) {
          if (arr[i] && Util.canonicalWidgetId(String(arr[i].id || "")) === ownId) {
            if (!replaced) {
              arr[i] = clean
              replaced = true
            } else {
              arr.splice(i, 1)
              i--
            }
          }
        }
      }
      if (!replaced) {
        if (!Array.isArray(config.bar.layout.right)) config.bar.layout.right = []
        config.bar.layout.right.unshift(clean)
      }
    })
  }

  IpcHandler {
    target: "monobar"

    // The picker sends its settings through here (base64 JSON) instead of
    // writing them itself: inside a replacement bar the widget only gets a
    // restricted shell facade, while the bar owns the config-mutation
    // capability. Writing through the bar keeps persistence working in every
    // hosting, and the shell.json write reloads the bar config in place —
    // the target screen moves the moment the picker is clicked.
    // (Returns a string: qmllint mishandles IpcHandlers mixing void and
    // string functions, and the caller ignores the answer anyway.)
    function apply(encoded: string): string {
      var entry = null
      try {
        entry = JSON.parse(Qt.atob(String(encoded || "")))
      } catch (e) {
        return "bad payload"
      }
      root.applyEntry(entry)
      return "ok"
    }

    function status(): string {
      var names = []
      var screens = Quickshell.screens || []
      for (var i = 0; i < screens.length; i++) names.push(String(screens[i].name || ""))
      var targets = []
      for (var j = 0; j < root.targetScreens.length; j++)
        targets.push(String(root.targetScreens[j].name || ""))
      return JSON.stringify({
        bar: root.ownId,
        mode: root.targetScreens.length ? "custom" : "all",
        targets: targets,
        monitors: root.selectedRefs,
        screens: names
      })
    }
  }
}
