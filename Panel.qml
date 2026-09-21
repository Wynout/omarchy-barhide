import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar Hide's screen picker popup. Lists every connected screen with its
// identity, and toggles which of them carry the bar. Settings persist in the
// picker's own bar.layout entry via updateEntryInline, which is the same
// write path the built-in clock uses for its format cycling.
//
// Visuals use the shell's kit: PanelHero header, PanelSectionHeader section
// labels, whole-row clickable cards (the Ui.Toggle pattern — row owns the
// click, ToggleSwitch is presentation only), and Ui.Button for actions.
Panel {
  id: root
  moduleName: "wynout.barhide"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // The bar tracks the widget mounted in its slot — Picker.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator and switchPanelFrom both look the slot up
  // through it.
  readonly property var barIdentity: hostWidget || root

  // The authoritative selection lives on the picker widget
  // (refreshSelection(), fed by its watched shell.json) — the same source
  // parking uses. Do NOT derive it from the injected `settings` property:
  // that write-path races the module injection order and was observed to
  // apply late via injectProps, which used to render every row as "hide".
  property var selectedRefs: []
  property var targetScreens: []

  // The connected subset, resolved with the same matcher the bar itself
  // uses — deduped by output name.
  readonly property var resolvedTargets: targetScreens

  function captureScreen(screen) {
    return {
      name: String(screen.name || ""),
      model: String(screen.model || ""),
      serial: String(screen.serial || "")
    }
  }

  function isSelected(screen) {
    for (var i = 0; i < selectedRefs.length; i++)
      if (Model.refMatches(selectedRefs[i], screen)) return true
    return false
  }

  // Effective bar state for a connected screen: with an empty selection the
  // bar is on every screen, so every screen reads "hide".
  function onBarNow(screen) {
    return selectedRefs.length === 0 ? true : isSelected(screen)
  }

  function toggleScreen(screen) {
    var list = []
    if (selectedRefs.length === 0) {
      // The bar covers every screen; hiding one pins it to the others.
      var screens = Quickshell.screens || []
      for (var i = 0; i < screens.length; i++) {
        var s = screens[i]
        if (s && s.name !== screen.name) list.push(captureScreen(s))
      }
    } else {
      for (var j = 0; j < selectedRefs.length; j++)
        if (!Model.refMatches(selectedRefs[j], screen)) list.push(selectedRefs[j])
      if (!isSelected(screen)) list.push(captureScreen(screen))
    }
    if (hostWidget && typeof hostWidget.applySettings === "function")
      hostWidget.applySettings({ monitors: list })
  }

  // Selected references whose monitor is not connected right now. They stay
  // in the list on purpose — their monitor should carry the bar when it
  // returns — but they need a way out.
  readonly property var unresolvedRefs: {
    var screens = Quickshell.screens || []
    var out = []
    for (var i = 0; i < selectedRefs.length; i++)
      if (Model.findScreen(screens, selectedRefs[i]) === null) out.push(selectedRefs[i])
    return out
  }

  // Connected screens currently without the bar — feeds the hero meta line.
  readonly property var hiddenNames: {
    var screens = Quickshell.screens || []
    var out = []
    for (var i = 0; i < screens.length; i++)
      if (!onBarNow(screens[i])) out.push(String(screens[i].name || ""))
    return out
  }

  readonly property int onCount: (Quickshell.screens || []).length - hiddenNames.length

  function forgetRef(ref) {
    var list = []
    for (var i = 0; i < selectedRefs.length; i++)
      if (!Model.refMatches(selectedRefs[i], ref)) list.push(selectedRefs[i])
    if (hostWidget && typeof hostWidget.applySettings === "function")
      hostWidget.applySettings({ monitors: list })
  }

  function clearAll() {
    if (hostWidget && typeof hostWidget.applySettings === "function")
      hostWidget.applySettings({ monitors: [] })
  }

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // One connected screen: a hoverable, whole-row clickable card. The
  // ToggleSwitch is presentation only — the row owns the click, exactly the
  // Ui.Toggle pattern — so the hit target is the full row.
  component ScreenRow: BorderSurface {
    id: rowRoot

    required property var modelData

    readonly property bool onBar: root.onBarNow(modelData)
    readonly property bool hot: rowMouse.containsMouse

    width: parent.width
    implicitHeight: rowLayout.implicitHeight + Style.space(12)
    radius: Style.cornerRadius

    color: Style.controlFill(false, hot, root.barForeground, Color.accent)
    borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", root.barForeground, Color.accent)
    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      // Bar-state dot: accent when the screen carries the bar, dim when not.
      Rectangle {
        id: statusDot
        width: Style.space(7)
        height: Style.space(7)
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: rowRoot.onBar ? Color.accent : Qt.darker(root.barForeground, 1.6)
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Column {
        width: rowLayout.width - statusDot.width - rowToggle.implicitWidth - rowLayout.spacing * 2
        spacing: Style.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: rowRoot.modelData.name
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: rowRoot.onBar
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: rowRoot.modelData.model || "unknown model"
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        id: rowToggle
        checked: rowRoot.onBar
        interactive: false
        cursorRing: false
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleScreen(rowRoot.modelData)
    }
  }

  // A selected reference whose monitor is away. Muted card; the only action
  // is forgetting it.
  component UnresolvedRow: BorderSurface {
    id: unresolvedRoot

    required property var modelData

    width: parent.width
    implicitHeight: unresolvedLayout.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.barForeground, Color.accent)
    borderSpec: Border.controlSpec("normal", root.barForeground, Color.accent)

    Row {
      id: unresolvedLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(8)

      Text {
        width: parent.width - forgetButton.implicitWidth - parent.spacing
        text: unresolvedRoot.modelData.name
          ? unresolvedRoot.modelData.name + " (not connected)"
          : "not connected"
        color: Color.muted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }

      // The kit's own row-edge forget/unpair affordance: quiet at rest,
      // urgent-tinted on hover.
      PanelActionButton {
        id: forgetButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uDB80\uDD59"
        tooltipText: "forget"
        foreground: Color.muted
        hoverColor: Color.urgent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.forgetRef(unresolvedRoot.modelData)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        // ---- Hero: glyph · title · hidden read-out · on/total pill
        PanelHero {
          width: parent.width
          title: "Bar Hide"
          meta: root.hiddenNames.length
            ? "hidden: " + root.hiddenNames.join(", ")
            : "none hidden"
          detail: root.onCount + "/" + (Quickshell.screens || []).length
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

          iconComponent: Text {
            textFormat: Text.PlainText
            // Same glyph as Picker.qml's widget button: U+F0DDC
            // md-monitor-star (the pinned monitor) — UTF-16 surrogate
            // escapes keep the source ASCII.
            text: "\uDB83\uDDDC"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
          }
        }

        PanelSeparator {}

        // ---- Connected screens
        PanelSectionHeader {
          text: "Screens"
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Repeater {
          model: Quickshell.screens

          delegate: ScreenRow {}
        }

        // ---- Selected but not connected: they keep their place in the
        // list until their monitor returns, but can be forgotten here.
        PanelSectionHeader {
          text: "Not connected"
          visible: root.unresolvedRefs.length > 0
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Repeater {
          model: root.unresolvedRefs

          delegate: UnresolvedRow {}
        }

        PanelSeparator {}

        // ---- Selection read-out (full picture, including not-connected refs)
        Text {
          width: parent.width
          text: root.selectedRefs.length
            ? "Bar on: " + root.selectedRefs.map(Model.refLabel).join(", ")
            : "Nothing hidden - bar on every screen."
          color: Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          text: "show on all"
          enabled: root.selectedRefs.length > 0
          opacity: enabled ? 1.0 : 0.4
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: root.clearAll()
        }
      }
    }
  }
}
