# Bar Hide — agent notes

## What this plugin is now (v0.4.0+)

An ordinary **bar-widget** plugin. Not a bar replacement. Each picker
instance lives inside its screen's native bar panel and parks its own
screen's panel when that screen is not selected. The bar is Omarchy's native
bar; Bar Hide only controls which screens carry it.

Entry points: `Picker.qml` (bar widget + parking mechanism), `Panel.qml`
(screen-selection popup), `Model.js` (screen-reference matching), and
`singles/BarHideState.qml` (shared state singleton, v0.4.1: one shell.json
FileView, one bar-off probe + watcher + 15s periodic re-probe for all picker
instances — before that, per-screen watchers could strand a screen and make
screens disagree about park state).

(Naming history: shipped v0.2–0.3 as `monobar` / MonoBar, when it still
replaced the whole bar; renamed to `barhide` / Bar Hide in v0.4 when it
became a plain widget.)

## Why it stopped being a `bar` kind plugin

The original v0.2 manifest declared `kinds: ["bar", "bar-widget"]` and
replaced the whole topbar by extending `qs.plugins.bar` (the topbar-peek
technique), parking the native panels it hosted.

That breaks service-backed third-party widgets by design: when a third-party
bar hosts widgets, Omarchy gives them a **service-less shell facade**
(`/usr/share/omarchy/shell/shell.qml`, see `pluginShellForBarEntry` and the
comment about replacement bars). E.g. the hass plugin reports "The Home
Assistant service did not start" — its `serviceFor("hass")` returns null by
shell-side security design. No plugin-side workaround exists. Converting to
a plain bar-widget restores full service-capable facades for every widget.

## How parking works (and why per-instance)

Each picker instance resolves its selection from the live shell.config
(`~/.config/omarchy/shell.json`, watched with FileView) and parks **its own
host panel**:

- `QsWindow.window` (Quickshell attached property) = the host BarPanel.
- A `Binding` with `when` + `restoreMode: Binding.RestoreBindingOrValue`
  writes `exclusionMode` (`Ignore` when parked, `Auto` otherwise) and the
  window `margins.<edge>` = `-barSize` when parked — the same mechanism
  the native bar-hidden toggle uses (BarPanel keeps the surface alive
  off-screen instead of unmapping it).
- Global `bar-off` toggle respected via the same bash-probe + directory
  watcher the native bar uses (`~/.local/state/omarchy/toggles/bar-off`).
  v0.4.1: the shared state re-probes on a 15s Timer as a fallback, because
  the directory watch can permanently stop delivering events after flag
  changes land in quick succession (the native bar solves the same problem
  with an IPC nudge; a plugin has no toggle-hook to receive one).
- Selection resolution order: `bar.barhide` override in shell.json >
  the widget's own `bar.layout` entry > injected `settings` (popup display
  only; parking stays "show all" until the config has been read once —
  `configReady` in the shared state gates parking so startup can't park
  from incomplete fallback data). The shared state also keeps the last
  good parse if shell.json is caught mid-write.
- Park Bindings own the host panel's exclusionMode/margins while alive
  (constant-true `when`); `Component.onDestruction` flips `teardown`,
  deactivating the Bindings so RestoreBindingOrValue restores the native
  values *before* the Bindings are destroyed — a widget removed while
  parked would otherwise strand its panel off-screen.
- `monitors` refs match `Model.js` rules: structured `{ name, model, serial }`
  scored (name +2, serial +1, model +1), ties refuse to guess; strings are
  case-insensitive substrings. Legacy `primary`/`secondary` still read.
  Screens chosen but disconnected stay pending (they return with the monitor).
- Options are keys next to `monitors` in the same entry
  (`showCountBadge` in v0.4.1, default true, resolved override > own entry >
  injected settings). The `applySettings` merge in Picker is what keeps a
  badge write from dropping `monitors` (and vice versa) — updateEntryInline
  replaces entries wholesale. The merge base is the widget's OWN entry, not
  the override: overriding contents must not leak into the widget entry. The
  options page is the hero cog in Panel.qml (`showOptions` swaps the popup's
  content column); rows follow the same row-owns-the-click card pattern.

### Key findings from the investigation (don't re-derive these)

1. **Window `parent` is not the QObject parent.** QML `Window.parent` = the
   transient/visual parent (null here). Quickshell's `Variants` sets the
   QObject parent of instances via `instance->setParent(variants)`, but that
   is unreachable from QML. Item parent chains dead-end at the window's
   contentItem. So "walk up to the Bar root and enumerate all panels" does
   **not** work; per-instance self-parking via the attached window is the
   only clean path.
2. **No window enumeration API** in Quickshell 0.3.1's singleton (`screens`
   only) — no way to find sibling panels without traversal.
3. **The injected `settings` property races.** Mounted with `{}`, updated
   later (module `injectProps`), and the property's notify was observed to
   not re-run multi-branch declarative bindings reliably. Hence: explicit
   `refreshSelection()` calls from `onSettingsChanged`,
   `Component.onCompleted`, screensChanged and the FileView, with the file
   itself as the authoritative source for parking decisions. The popup
   (Panel.qml) had the same bug the other way: it derived its own
   selectedRefs from injected `settings`, so the screen list rendered every
   row as "hide" whenever `settings` had not arrived. Fixed by binding
   Panel's `selectedRefs`/`targetScreens` to the picker widget's
   authoritative props in `injectPanel()` (Qt.binding) — the popup and the
   parking now share one source.
4. **Hyprland layer rules cannot park a bar** (top layer surface): no rule
   hides a layer per monitor, and opacity/blur do not release the exclusive
   zone, so the compositor route was not viable.
5. **Editing plugin files does not hot-swap running widget code.** The shell
   re-registers the same (stale) `Component` object when the entry URL is
   unchanged. After editing QML, run `omarchy restart shell`.

## Trade-offs & known limitations (accepted)

- **Tied to native internals.** Parking depends on the native BarPanel's
  properties (`exclusionMode`, `margins`, `screen`) and on `PluginBarApi`
  exposing `barSize`/`position`. An Omarchy update could break parking;
  guards (`property in target` checks in the Bindings' `when`) make it fail
  safe to "no parking" (bar on every screen) rather than erroring.
- **The picker must stay on the bar.** Removing the widget (or disabling the
  plugin) removes the parking logic entirely — native behavior resumes. If
  you want the feature back after a removal, re-add the widget.
- **Drag/move ghost panels are not parked.** They are separate windows not
  hosting the picker, unreachable by design. Cosmetic only: during an active
  widget drag, a small preview may appear on a non-selected screen.
- **Parked screens stay alive off-screen** (timers, fetches keep running) —
  same behavior as the native bar-hidden toggle; done so the bar returns in
  ~20ms instead of rebuilding its scene graph (~150ms).
- **`bar.barhide` override still works** (watched via FileView), but
  `autoInsertPicker` is gone (obsolete — enabling places the widget) and the
  `monobar` IPC target that existed under the plugin's original `monobar`
  id) was removed with the old bar entry point.
- Any plugin needing a *service* (e.g. hass) works fine inside the native
  bar; when Bar Hide was the bar, such widgets could not work. This is shell
  security design, not a Bar Hide bug.
- **`omarchy plugin update` overwrites this live directory** with the git
  copy. Keep the source of truth elsewhere (`~/dev/omarchy-barhide`) and re-apply.

## Legacy

The v0.2 bar-replacement implementation (`Bar.qml` + old manifest) was
archived in git history — commit "Archive v0.2 bar-replacement
implementation", before v0.4.0 — and removed from the tree in v0.4.
Recover it with `git checkout <sha> -- legacy-bar-mode/` if Omarchy ever
supports service-scoped facades for replacement bars (upstream roadmap
candidate: let replacement bars hand hosted widgets their own plugin-scoped
service facade; the bar itself would still not access other plugins'
services).

## Verification

```bash
PLUGIN_DIR=~/.config/omarchy/plugins/wynout.barhide
omarchy plugin validate "$PLUGIN_DIR"
qmllint -I "$OMARCHY_PATH/shell" "$PLUGIN_DIR/Picker.qml" "$PLUGIN_DIR/Panel.qml"
omarchy restart shell
# bar surfaces per monitor; parked ones sit one bar-size past the top edge
hyprctl layers | awk '/^Monitor/{mon=$2} /omarchy-bar/{print mon, $0}'
# and park state survives `omarchy toggle bar off` / on again
```
