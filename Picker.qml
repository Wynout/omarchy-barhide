import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "./singles" as BH
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
// Selection and the bar-hidden flag are shared state (BH.BarHideState); each
// picker only decides whether to park its own host panel, so screens can
// never disagree about park state.
//
// Structurally the built-in clock: this entry point owns the bar slot and
// forwards the panel lifecycle, Panel.qml owns the popup content.
BarWidget {
  id: root
  moduleName: "wynout.barhide"

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

  function toggle() {
    togglePanel()
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
    // the rows would all render as "hide". Bind, so every selection change
    // (here and in the shared state) reaches the popup without re-injection.
    if ("selectedRefs" in target)
      target.selectedRefs = Qt.binding(function() { return root.selectedRefs })
    if ("targetScreens" in target)
      target.targetScreens = Qt.binding(function() { return root.targetScreens })
  }

  // The picker mirrors the settings it writes: applied locally first so the
  // row badges move on the click itself, then persisted through
  // updateEntryInline — the widget-shell path for writing a widget's own
  // layout entry, the same write the built-in clock uses for its format
  // cycling. The shell.json write reloads the bar config in place and the
  // shared state re-resolves for every instance from the same watched file.
  //
  // Payloads merge into the current settings (start from the authoritative
  // entry, not just what this write carries) so a badge toggle never drops
  // `monitors` and a screen toggle never drops option keys — updateEntryInline
  // replaces entries wholesale.
  function applySettings(next) {
    var entry = { id: root.moduleName }
    // Base is the widget's OWN entry (never the bar.barhide override — that
    // is a hand-edit box and must not leak its contents into the widget's
    // entry on the next write). The next write's keys win.
    var base = BH.BarHideState.configReady
      ? BH.BarHideState.ownEntryFromConfig
      : root.settings
    if (Util.isPlainObject(base))
      for (var bk in base)
        if (bk !== "id") entry[bk] = base[bk]
    for (var key in next)
      if (key !== "id") entry[key] = next[key]
    // Legacy keys the current shape replaced are not carried forward.
    delete entry.primary
    delete entry.secondary
    var payload = {}
    for (var pk in entry)
      if (pk !== "id") payload[pk] = entry[pk]
    root.settings = entry
    // Optimistic state update: the popup and every park decision recompute
    // now, before the write even lands. previewEntry writes the same slot
    // the file-parse writes, so nothing disagrees once the file confirms.
    BH.BarHideState.previewEntry(payload)
    if (!root.bar || !root.bar.shell
        || typeof root.bar.shell.updateEntryInline !== "function") return
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Settings -------------------------------------------------------------

  // The shared state's shell.json watcher is this widget's authoritative
  // source; the injected `settings` property was observed to race the module
  // injection order, so it only feeds the popup's pre-config fallback.
  // Resolution order: 1. `bar.barhide` hand-edit override, 2. this widget's
  // own bar.layout entry, 3. (until the config has been read once) the
  // injected `settings` for popup display — parking itself stays native
  // "show all" until the config speaks.
  readonly property var selectedRefs: BH.BarHideState.configReady
    ? BH.BarHideState.selectedRefs
    : (BH.BarHideState.refsOf(root.settings) || [])
  readonly property var targetScreens: BH.BarHideState.targetScreens

  readonly property bool hasTarget: root.selectedRefs.length > 0

  function shouldShow(screen) {
    if (root.targetScreens.length === 0) return true
    for (var i = 0; i < root.targetScreens.length; i++)
      if (root.targetScreens[i] === screen
          || (screen && root.targetScreens[i].name === screen.name)) return true
    return false
  }

  // ---- Self-parking ---------------------------------------------------------

  // This widget instance lives inside its own screen's bar panel; the
  // attached QsWindow is that panel. Every instance parks only its own host,
  // so there is no cross-window coordination and no reliance on the native
  // bar's object tree.
  readonly property var hostWindow: QsWindow.window
  readonly property var hostScreen: hostWindow ? hostWindow.screen : null
  // configReady gates parking: before the shared state has read shell.json
  // at least once, an empty/incomplete fallback must not park a bar that the
  // user asked for. The global bar-hidden flag needs no gate — its probe is
  // independent of the config file.
  readonly property bool parked: BH.BarHideState.barHidden
    || (BH.BarHideState.configReady && !root.shouldShow(root.hostScreen))
  readonly property real parkedOffset: root.parked
    ? -Math.max(root.bar && root.bar.barSize > 0 ? root.bar.barSize : 26, 26)
    : 0

  // While parked, these Bindings own the host panel's exclusion mode and
  // margins. Their `when` guards are intentionally always-true once the host
  // exists: the value expressions cover both parked and shown states, and
  // this way the native bindings (which they displaced) are restored on the
  // one deactivation that matters — teardown. Set `teardown` first in
  // Component.onDestruction: the deactivation restores the previous
  // binding/value (RestoreBindingOrValue) while the Binding is still alive,
  // so a widget removed while parked cannot strand its panel off-screen.
  property bool teardown: false

  Component.onDestruction: {
    root.teardown = true
  }

  Binding {
    target: root.hostWindow
    property: "exclusionMode"
    value: root.parked ? ExclusionMode.Ignore : ExclusionMode.Auto
    when: root.hostWindow !== null && "exclusionMode" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.top"
    value: root.bar && root.bar.position === "top" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.bottom"
    value: root.bar && root.bar.position === "bottom" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.left"
    value: root.bar && root.bar.position === "left" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.right"
    value: root.bar && root.bar.position === "right" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  // ---- Bar slot ------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    // The injected settings only matter before the config file has been
    // read; mirror them into the shared state so the options page resolves
    // `showCountBadge` from the same fallback as everything else.
    BH.BarHideState.sandboxEntry = root.settings
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
    // Nerd Font glyph via the shared catalog (see OptionGlyphs for why
    // astral-plane source stays escaped). With a selection the widget
    // carries a count badge, so the state is readable without opening
    // the popup. The icon is user-settable: `pickerGlyph` option.
    text: BH.BarHideState.showCountBadge && root.hasTarget
      ? BH.BarHideState.pickerGlyph + " " + root.selectedRefs.length
      : BH.BarHideState.pickerGlyph
    tooltipText: root.hasTarget
      ? "Bar Hide: bar on " + root.selectedRefs.map(Model.refLabel).join(" · ")
      : "Bar Hide: bar on every screen"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
    }
  }
}
