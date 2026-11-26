import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "./singles" as BH
import "Model.js" as Model

// Hide Bar's picker: a bar button that opens the screen-selection panel, and
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
    if ("displayMode" in target)
      target.displayMode = Qt.binding(function() { return root.displayMode })
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
    // Drop the removed fullscreen-video preference from pre-release configs.
    delete entry.hideOnFullscreenMonitors
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
  readonly property string displayMode: BH.BarHideState.displayMode

  readonly property bool hasTarget: root.selectedRefs.length > 0

  function shouldShowPerMonitor(screen) {
    if (root.targetScreens.length === 0) return true
    for (var i = 0; i < root.targetScreens.length; i++)
      if (root.targetScreens[i] === screen
          || (screen && root.targetScreens[i].name === screen.name)) return true
    return false
  }

  function shouldShow(screen) {
    if (root.displayMode === "show-all" || root.displayMode === "autohide-all") return true
    return root.shouldShowPerMonitor(screen)
  }

  function shouldAutohidePerMonitor(screen) {
    var targets = BH.BarHideState.autohideTargetScreens
    for (var i = 0; i < targets.length; i++)
      if (targets[i] === screen || (screen && targets[i].name === screen.name)) return true
    return false
  }

  function shouldAutohide(screen) {
    if (root.displayMode === "show-all") return false
    if (root.displayMode === "autohide-all") return true
    return root.shouldAutohidePerMonitor(screen)
  }

  function sectionVisible(screen, section) {
    if (root.displayMode === "show-all") return true
    var values = Model.sectionZonesForScreen(
      BH.BarHideState.sectionZoneRecords, screen, Quickshell.screens || [])
    return values[String(section)] !== false
  }

  function toggleSection(screen, section) {
    if (!screen) return
    var current = root.sectionVisible(screen, section)
    var next = Model.setSectionZone(
      BH.BarHideState.sectionZoneRecords, screen, section, !current,
      Quickshell.screens || [])
    if (next !== null) {
      var update = { sectionZones: next }
      if (root.displayMode !== "per-monitor") update.displayMode = "per-monitor"
      root.applySettings(update)
    }
  }

  function setDisplayMode(mode) {
    if (mode !== "per-monitor" && mode !== "show-all" && mode !== "autohide-all") return
    if (mode === "show-all") {
      // "Show everywhere" is also the reset action for per-screen visibility:
      // clear bar, autohide, and section-zone exceptions.
      root.applySettings({
        displayMode: mode,
        monitors: [],
        autohideMonitors: [],
        sectionZones: []
      })
      return
    }
    root.applySettings({ displayMode: mode })
  }

  function setScreenEnabled(screen, enabled) {
    if (!screen) return
    var refs = BH.BarHideState.selectedRefs
    var screens = Quickshell.screens || []
    var list = []
    var found = false

    if (refs.length === 0) {
      if (enabled) return
      // An empty selection means all screens. Pin the bar to every other
      // connected screen when hiding one from that state.
      if (screens.length <= 1) return
      for (var i = 0; i < screens.length; i++)
        if (screens[i] && String(screens[i].name || "") !== String(screen.name || ""))
          list.push({
            name: String(screens[i].name || ""),
            model: String(screens[i].model || ""),
            serial: String(screens[i].serial || "")
          })
    } else {
      for (var j = 0; j < refs.length; j++) {
        if (Model.findScreen(screens, refs[j]) === screen) found = true
        else list.push(refs[j])
      }
      if (enabled && !found) {
        list.push({
          name: String(screen.name || ""),
          model: String(screen.model || ""),
          serial: String(screen.serial || "")
        })
      } else if (!enabled && found && list.length === 0) {
        // Keep one bar reachable; use the global bar-off switch to hide all.
        return
      }
    }

    var next = { monitors: list }
    if (root.displayMode === "show-all") next.displayMode = "per-monitor"
    root.applySettings(next)
  }

  function toggleAutohide(screen) {
    if (!screen) return
    var refs = BH.BarHideState.autohideRefs
    var list = []
    var found = false
    var screens = Quickshell.screens || []
    for (var i = 0; i < refs.length; i++) {
      if (Model.findScreen(screens, refs[i]) === screen) found = true
      else list.push(refs[i])
    }
    var desired = root.displayMode === "per-monitor"
      ? !root.shouldAutohidePerMonitor(screen)
      : !root.shouldAutohide(screen)
    if (desired && !found)
      list.push({
        name: String(screen.name || ""),
        model: String(screen.model || ""),
        serial: String(screen.serial || "")
      })
    var next = { autohideMonitors: list }
    // A per-screen Auto-hide click while in a global mode is an explicit
    // request to customize this monitor. Switch to per-monitor mode and apply
    // the clicked value; all other saved per-monitor choices resume.
    if (root.displayMode !== "per-monitor") {
      next.displayMode = "per-monitor"
      // Global modes show every bar. If this screen was disabled in the
      // saved per-monitor selection, keep it enabled so turning Auto-hide
      // off produces an always-visible bar rather than a hidden one.
      if (!root.shouldShowPerMonitor(screen) && root.selectedRefs.length > 0) {
        var shownRefs = []
        for (var j = 0; j < root.selectedRefs.length; j++)
          shownRefs.push(root.selectedRefs[j])
        shownRefs.push({
          name: String(screen.name || ""),
          model: String(screen.model || ""),
          serial: String(screen.serial || "")
        })
        next.monitors = shownRefs
      }
    }
    // Auto-hide is an independent preference. It never enables or disables
    // the bar on a screen; that remains the separate `monitors` setting.
    root.applySettings(next)
  }

  // Section discovery follows the ModuleList marker strategy used by
  // ApachaiZ's MIT-licensed Per-Screen Zones plugin. See THIRD_PARTY_NOTICES.md.
  function zoneForRegion(region) {
    var name = String(region || "")
    if (name === "left" || name === "right") return name
    if (name === "center" || name === "centerBegin" || name === "centerEnd") return "center"
    return ""
  }

  function scanSections() {
    var out = {
      left: { containers: [], slots: [] },
      center: { containers: [], slots: [] },
      right: { containers: [], slots: [] }
    }
    var win = root.hostWindow
    if (!win || !win.contentItem) return out
    var stack = [win.contentItem]
    var guard = 0
    while (stack.length > 0 && guard < 20000) {
      guard++
      var item = stack.pop()
      if (!item) continue
      if (item.keys !== undefined && item.region !== undefined) {
        var zone = root.zoneForRegion(item.region)
        if (!zone) continue
        out[zone].containers.push(item)
        var slots = item.children
        if (slots) for (var s = 0; s < slots.length; s++) {
          var slot = slots[s]
          if (slot && slot.region !== undefined && root.zoneForRegion(slot.region) === zone)
            out[zone].slots.push(slot)
        }
        continue
      }
      var kids = item.children
      if (kids) for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return out
  }

  function refreshSectionTargets() {
    var found = root.scanSections()
    root.leftSectionContainers = found.left.containers
    root.leftSectionSlots = found.left.slots
    root.centerSectionContainers = found.center.containers
    root.centerSectionSlots = found.center.slots
    root.rightSectionContainers = found.right.containers
    root.rightSectionSlots = found.right.slots
  }

  component SectionContainerBinding: Item {
    id: containerBinding
    required property var targetItem
    required property bool shown
    visible: false
    width: 0
    height: 0

    Binding {
      target: containerBinding.targetItem
      property: "opacity"
      value: 0
      when: containerBinding.targetItem !== null && !containerBinding.shown
      restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
      target: containerBinding.targetItem
      property: "enabled"
      value: false
      when: containerBinding.targetItem !== null && !containerBinding.shown
      restoreMode: Binding.RestoreBindingOrValue
    }
  }

  component SectionSlotBinding: Item {
    id: slotBinding
    required property var targetItem
    required property bool shown
    visible: false
    width: 0
    height: 0

    Binding {
      target: slotBinding.targetItem
      property: "visible"
      value: false
      when: slotBinding.targetItem !== null && !slotBinding.shown
      restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
      target: slotBinding.targetItem
      property: "enabled"
      value: false
      when: slotBinding.targetItem !== null && !slotBinding.shown
      restoreMode: Binding.RestoreBindingOrValue
    }
  }

  // ---- Self-parking ---------------------------------------------------------

  // This widget instance lives inside its own screen's bar panel; the
  // attached QsWindow is that panel. Every instance parks only its own host,
  // so there is no cross-window coordination and no reliance on the native
  // bar's object tree.
  readonly property var hostWindow: QsWindow.window
  readonly property var hostScreen: hostWindow ? hostWindow.screen : null
  property var leftSectionContainers: []
  property var leftSectionSlots: []
  property var centerSectionContainers: []
  property var centerSectionSlots: []
  property var rightSectionContainers: []
  property var rightSectionSlots: []
  // configReady gates parking: before the shared state has read shell.json
  // at least once, an empty/incomplete fallback must not park a bar that the
  // user asked for. The global bar-hidden flag needs no gate — its probe is
  // independent of the config file.
  readonly property bool parked: BH.BarHideState.barHidden
    || (BH.BarHideState.configReady && !root.shouldShow(root.hostScreen))
  // Whether the native bar panel spans its whole screen. Omarchy 4.5's bar
  // redesign (Bar.qml: BarPanel) made the panel a full-screen transparent
  // surface (implicitHeight = screen height) with the strip drawn inside;
  // before that, the panel WAS the strip (implicitHeight = barSize). Older
  // versions never published a compatibility flag, so detect the shape:
  // anything taller than the strip by a comfortable margin is a spanning
  // panel.
  readonly property real panelSpanLength: root.hostWindow && root.bar
    ? (root.bar.vertical ? root.hostWindow.implicitWidth : root.hostWindow.implicitHeight)
    : 0
  readonly property bool spanningPanel: root.hostWindow && root.bar
    && root.panelSpanLength > 0
    && root.bar.barSize > 0
    && root.panelSpanLength > root.bar.barSize + 4

  // Compatibility note: the spanning-panel detection keeps static parking
  // working on both the old strip panels and Omarchy 4.5+'s full-screen panel.
  // Autohide intentionally uses the latter only.
  readonly property real parkedOffset: root.parked
    // Park by the panel's full implicit size, the same distance the native
    // bar-hidden toggle uses: in v4.5 that is the whole screen (parking by
    // the strip's thickness would still cover the workspace), on older bars
    // the panel is the strip, so its size is the whole panel.
    ? -(root.spanningPanel ? root.panelSpanLength
      : Math.max(root.bar && root.bar.barSize > 0 ? root.bar.barSize : 26, 26))
    : 0

  // Autohide uses the native full-screen panel only on Omarchy 4.5+. Older
  // strip-sized panels retain the existing per-monitor show/hide behavior.
  readonly property bool autoHideSupported: root.spanningPanel
  readonly property bool sectionZonesSupported: root.spanningPanel
  readonly property bool autoHideEnabledHere: root.autoHideSupported
    && !BH.BarHideState.barHidden
    && BH.BarHideState.configReady
    && root.shouldShow(root.hostScreen)
    && root.shouldAutohide(root.hostScreen)
  readonly property real autoHideThickness: root.hostWindow
    && root.hostWindow.thickness > 0
      ? root.hostWindow.thickness
      : Math.max(root.bar && root.bar.barSize > 0 ? root.bar.barSize : 26, 26)
  property bool autoHideRevealed: false
  property bool autoHideEngaged: false
  property real autoHideOffset: -root.autoHideThickness
  readonly property real panelOffset: root.parked
    ? root.parkedOffset
    : (root.autoHideEnabledHere ? root.autoHideOffset : 0)
  readonly property bool autoHideBarHovered: autoHideBarHover.hovered
  readonly property bool autoHidePopoutHere: {
    var owner = root.bar ? root.bar.activePopout : null
    return !!owner && root.hostWindow
      && typeof root.bar.targetBelongsToWindow === "function"
      && root.bar.targetBelongsToWindow(owner, root.hostWindow)
  }
  readonly property bool autoHideHeld: root.autoHideBarHovered
    || (edgeTrigger.visible && edgeTrigger.hovered)
    || root.autoHidePopoutHere
    || (root.bar && root.bar.traySectionDragActive === true)

  function setAutoHideRevealed(value) {
    if (!root.autoHideEnabledHere) return
    autoHideSlide.stop()
    if (value) {
      if (!root.autoHideEngaged) {
        root.autoHideOffset = -root.autoHideThickness
        root.autoHideEngaged = true
      }
      root.autoHideRevealed = true
      autoHideSlide.duration = Style.duration(160)
      autoHideSlide.to = 0
      if (autoHideSlide.duration <= 0) {
        root.autoHideOffset = 0
      } else {
        autoHideSlide.start()
      }
    } else {
      root.autoHideRevealed = false
      autoHideSlide.duration = Style.duration(120)
      autoHideSlide.to = -root.autoHideThickness
      if (autoHideSlide.duration <= 0) {
        root.autoHideOffset = -root.autoHideThickness
        root.autoHideEngaged = false
      } else {
        autoHideSlide.start()
      }
    }
  }

  onAutoHideEnabledHereChanged: {
    if (!autoHideEnabledHere) {
      autoHideSlide.stop()
      autoHideRevealed = false
      autoHideEngaged = false
      autoHideOffset = -autoHideThickness
    }
  }

  onAutoHideThicknessChanged: {
    if (!autoHideEngaged) autoHideOffset = -autoHideThickness
  }

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
    // Adaptive (see spanningPanel above): a spanning panel (v4.5+) sets its
    // own explicit strip-sized exclusive zone, so Normal is the native move;
    // the older strip panel derived its reservation from Auto. Ignore is the
    // park. Without this Binding the native values stand whenever parked is
    // false, so the split only matters while this widget owns the panel.
    value: root.parked || root.autoHideEnabledHere ? ExclusionMode.Ignore
      : (root.spanningPanel ? ExclusionMode.Normal : ExclusionMode.Auto)
    when: root.hostWindow !== null && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.top"
    value: root.bar && root.bar.position === "top" ? root.panelOffset : 0
    when: root.hostWindow !== null && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.bottom"
    value: root.bar && root.bar.position === "bottom" ? root.panelOffset : 0
    when: root.hostWindow !== null && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.left"
    value: root.bar && root.bar.position === "left" ? root.panelOffset : 0
    when: root.hostWindow !== null && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.right"
    value: root.bar && root.bar.position === "right" ? root.panelOffset : 0
    when: root.hostWindow !== null && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow ? root.hostWindow.WlrLayershell : null
    property: "layer"
    value: WlrLayer.Overlay
    when: root.autoHideEngaged && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  readonly property bool autoHideFullscreenInput: root.autoHideEngaged
    && root.hostWindow && root.hostWindow.underFullscreen === true

  Region {
    id: autoHideInputRegion
    x: root.bar && root.bar.position === "right"
      ? Math.max(0, (root.hostWindow ? root.hostWindow.width : 0) - root.autoHideThickness) : 0
    y: root.bar && root.bar.position === "bottom"
      ? Math.max(0, (root.hostWindow ? root.hostWindow.height : 0) - root.autoHideThickness) : 0
    width: root.bar && root.bar.vertical ? root.autoHideThickness
      : (root.hostWindow ? root.hostWindow.width : 0)
    height: root.bar && root.bar.vertical
      ? (root.hostWindow ? root.hostWindow.height : 0) : root.autoHideThickness
  }

  Binding {
    target: root.hostWindow
    property: "mask"
    value: autoHideInputRegion
    when: root.autoHideFullscreenInput && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  HoverHandler {
    id: autoHideBarHover
    parent: root.hostWindow ? root.hostWindow.contentItem : null
    blocking: false
    enabled: root.autoHideEnabledHere
    onHoveredChanged: if (hovered) root.setAutoHideRevealed(true)
  }

  Timer {
    id: autoHideTimer
    interval: 250
    running: root.autoHideEnabledHere && root.autoHideRevealed && !root.autoHideHeld
    onTriggered: if (!root.autoHideHeld) root.setAutoHideRevealed(false)
  }

  NumberAnimation {
    id: autoHideSlide
    target: root
    property: "autoHideOffset"
    duration: Style.duration(160)
    easing.type: Easing.OutCubic
    onFinished: if (!root.autoHideRevealed) root.autoHideEngaged = false
  }

  component EdgeTrigger: PanelWindow {
    id: edge
    required property var widget
    readonly property string edgeName: widget.bar ? widget.bar.position : "top"
    readonly property bool verticalEdge: edgeName === "left" || edgeName === "right"
    readonly property bool hovered: edgeHover.hovered
    readonly property bool catching: visible
      && (!widget.autoHideRevealed || !widget.autoHideBarHovered)

    screen: widget.hostScreen
    visible: widget.autoHideEnabledHere
    color: "transparent"
    implicitWidth: verticalEdge ? 2 : 0
    implicitHeight: verticalEdge ? 0 : 2
    anchors {
      top: edgeName === "top" || edgeName === "left" || edgeName === "right"
      bottom: edgeName === "bottom" || edgeName === "left" || edgeName === "right"
      left: edgeName === "left" || edgeName === "top" || edgeName === "bottom"
      right: edgeName === "right" || edgeName === "top" || edgeName === "bottom"
    }
    exclusionMode: ExclusionMode.Ignore
    mask: edgeInputRegion
    WlrLayershell.namespace: "wynout-barhide-edge"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Region {
      id: edgeInputRegion
      width: edge.catching ? edge.width : 0
      height: edge.catching ? edge.height : 0
    }

    HoverHandler {
      id: edgeHover
      onHoveredChanged: if (hovered) edge.widget.setAutoHideRevealed(true)
    }
  }

  EdgeTrigger {
    id: edgeTrigger
    widget: root
  }

  Repeater {
    model: root.leftSectionContainers
    delegate: Item {
      id: leftContainerDelegate
      required property var modelData
      visible: false
      width: 0
      height: 0
      SectionContainerBinding {
        targetItem: leftContainerDelegate.modelData
        shown: root.sectionVisible(root.hostScreen, "left")
      }
    }
  }
  Repeater {
    model: root.leftSectionSlots
    delegate: Item {
      id: leftSlotDelegate
      required property var modelData
      visible: false
      width: 0
      height: 0
      SectionSlotBinding {
        targetItem: leftSlotDelegate.modelData
        shown: root.sectionVisible(root.hostScreen, "left")
      }
    }
  }
  Repeater {
    model: root.centerSectionContainers
    delegate: Item {
      id: centerContainerDelegate
      required property var modelData
      visible: false
      width: 0
      height: 0
      SectionContainerBinding {
        targetItem: centerContainerDelegate.modelData
        shown: root.sectionVisible(root.hostScreen, "center")
      }
    }
  }
  Repeater {
    model: root.centerSectionSlots
    delegate: Item {
      id: centerSlotDelegate
      required property var modelData
      visible: false
      width: 0
      height: 0
      SectionSlotBinding {
        targetItem: centerSlotDelegate.modelData
        shown: root.sectionVisible(root.hostScreen, "center")
      }
    }
  }
  Repeater {
    model: root.rightSectionContainers
    delegate: Item {
      id: rightContainerDelegate
      required property var modelData
      visible: false
      width: 0
      height: 0
      SectionContainerBinding {
        targetItem: rightContainerDelegate.modelData
        shown: root.sectionVisible(root.hostScreen, "right")
      }
    }
  }
  Repeater {
    model: root.rightSectionSlots
    delegate: Item {
      id: rightSlotDelegate
      required property var modelData
      visible: false
      width: 0
      height: 0
      SectionSlotBinding {
        targetItem: rightSlotDelegate.modelData
        shown: root.sectionVisible(root.hostScreen, "right")
      }
    }
  }

  Component.onCompleted: Qt.callLater(root.refreshSectionTargets)
  onHostWindowChanged: Qt.callLater(root.refreshSectionTargets)

  // Native bar sections can be rebuilt for position/layout changes. A slow
  // rescan reapplies the same per-monitor section settings after such rebuilds.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refreshSectionTargets()
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
      ? "Hide Bar: bar on " + root.selectedRefs.map(Model.refLabel).join(" · ")
      : "Hide Bar: bar on every screen"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
    }
  }
}
