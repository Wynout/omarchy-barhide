import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "./singles" as BH
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

  // The options page swap inside the popup; the hero cog toggles it.
  property bool showOptions: false

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

  function captureScreen(screen) {
    return {
      name: String(screen.name || ""),
      model: String(screen.model || ""),
      serial: String(screen.serial || "")
    }
  }

  // Whether a stored reference identifies this screen — using the same
  // resolution semantics as parking (Model.findScreen against the live
  // screens), not just the stored-field echo of refMatches. refMatches alone
  // lied after a re-plug: a monitor moved to another port changes its name,
  // the bar correctly carried it via serial/model scoring, but the row read
  // "off" and toggling it stacked a second, near-duplicate ref.
  function refResolvesTo(ref, screen) {
    if (!ref || !screen) return false
    if (Model.refMatches(ref, screen)) return true
    var resolved = Model.findScreen((Quickshell.screens || []), ref)
    return resolved === screen
  }

  function isSelected(screen) {
    for (var i = 0; i < selectedRefs.length; i++)
      if (refResolvesTo(selectedRefs[i], screen)) return true
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
        if (!refResolvesTo(selectedRefs[j], screen)) list.push(selectedRefs[j])
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

  // "1920×1080", or "" when the shell does not expose the geometry.
  function resolutionLabel(screen) {
    var w = 0
    var h = 0
    if (screen && screen.width > 0) w = screen.width
    if (screen && screen.height > 0) h = screen.height
    return w > 0 && h > 0 ? w + "×" + h : ""
  }

  // The edge a screen's bar sits on, per the native bar's position.
  readonly property string barEdge: root.bar && root.bar.position
    ? root.bar.position : "top"

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

      // A tiny monitor with placeholder bars: drawn per row so the list
      // shows where the bar sits (top/bottom/left/right per the native bar's
      // position) and which screens currently carry one — accent-lit when
      // on, dimmed when parked.
      Item {
        id: miniMonitor
        width: Style.space(46)
        height: Style.space(30)
        opacity: rowRoot.onBar ? 1.0 : 0.5
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          radius: Style.space(3)
          border.width: 1
          border.color: rowRoot.onBar
            ? Color.accent : Qt.darker(root.barForeground, 1.3)
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        Rectangle {
          id: miniBar
          readonly property bool vert: root.barEdge === "left" || root.barEdge === "right"

          anchors.margins: Style.space(3)
          anchors.horizontalCenter: root.barEdge === "top" || root.barEdge === "bottom"
            ? parent.horizontalCenter : undefined
          anchors.verticalCenter: vert ? parent.verticalCenter : undefined
          anchors.top: root.barEdge === "top" ? parent.top : undefined
          anchors.bottom: root.barEdge === "bottom" ? parent.bottom : undefined
          anchors.left: root.barEdge === "left" ? parent.left : undefined
          anchors.right: root.barEdge === "right" ? parent.right : undefined
          width: vert ? Style.space(3) : parent.width - anchors.margins * 2
          height: vert ? parent.height - anchors.margins * 2 : Style.space(3)
          radius: Style.space(1)
          color: rowRoot.onBar ? Color.accent : Qt.darker(root.barForeground, 1.4)
          opacity: rowRoot.onBar ? 1.0 : 0.4
          Behavior on color { ColorAnimation { duration: 120 } }
        }
      }

      Column {
        width: rowLayout.width - miniMonitor.width - rowToggle.implicitWidth - rowLayout.spacing * 2
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
          text: (rowRoot.modelData.model || "unknown model")
            + (root.resolutionLabel(rowRoot.modelData) !== ""
              ? " · " + root.resolutionLabel(rowRoot.modelData) : "")
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

  // A selected reference whose monitor is away. Muted card with an urgent
  // left edge so the "screen missing, bar pending" state is visible at a
  // glance; the only action is forgetting it.
  component UnresolvedRow: BorderSurface {
    id: unresolvedRoot

    required property var modelData

    width: parent.width
    implicitHeight: unresolvedLayout.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.barForeground, Color.accent)
    borderSpec: Border.withWidth(Border.flat(Color.urgent, 0), "0 0 0 2")

    Row {
      id: unresolvedLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX + 2
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

        // ---- Hero: glyph · title · hidden read-out · on/total pill · cog
        PanelHero {
          width: parent.width
          title: "Bar Hide"
          meta: root.showOptions
            ? "options"
            : (root.hiddenNames.length
              ? "hidden: " + root.hiddenNames.join(", ")
              : "none hidden")
          detail: root.onCount + "/" + (Quickshell.screens || []).length
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

          // The cog: flips the popup between the screen list and the options
          // page (v0.4.1: badge visibility; more settings can follow).
          // Alignment: the kit centers the trailing control against the
          // whole hero (title row + meta caption). The detail pill sits on
          // the title row, so the cog must ride up by half the meta caption
          // + row spacing to share its center line.
          trailingControl: Component {
            Item {
              implicitWidth: heroCog.implicitWidth
              implicitHeight: heroCog.implicitHeight

              PanelActionButton {
                id: heroCog
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Style.space(6)
                iconText: root.showOptions ? "\uDB81\uDC11" : "\uDB81\uDC93"
                tooltipText: root.showOptions ? "back to screens" : "options"
                foreground: Color.muted
                hoverColor: Color.accent
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                onClicked: root.showOptions = !root.showOptions
              }
            }
          }

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

        // ---- Screens view
        Column {
          visible: !root.showOptions
          width: parent.width
          spacing: Style.space(10)

        // ---- Connected screens
        PanelSectionHeader {
          text: "Toggle bars per screen"
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
          bordered: true
          enabled: root.selectedRefs.length > 0
          opacity: enabled ? 1.0 : 0.4
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: root.clearAll()
        }
        }

        // ---- Options page (hero cog): whole-row toggle cards, same
        // row-owns-the-click pattern as the screen list.
        Column {
          visible: root.showOptions
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "Options"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          BorderSurface {
            id: badgeRow
            width: parent.width
            implicitHeight: badgeRowLayout.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: Style.controlFill(false, badgeMouse.containsMouse, root.barForeground, Color.accent)
            borderSpec: Border.controlSpec(badgeMouse.containsMouse ? "hover-cursor" : "normal", root.barForeground, Color.accent)
            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
              id: badgeRowLayout
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.rightMargin: Style.spacing.rowPaddingX
              spacing: Style.space(10)

              Column {
                width: parent.width - badgeToggle.implicitWidth - parent.spacing
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  width: parent.width
                  text: "Selection count badge"
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: "Show how many screens carry the bar, next to the picker icon."
                  color: Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              ToggleSwitch {
                id: badgeToggle
                checked: BH.BarHideState.showCountBadge
                interactive: false
                cursorRing: false
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: badgeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.hostWidget && typeof root.hostWidget.applySettings === "function")
                  root.hostWidget.applySettings({
                    showCountBadge: !BH.BarHideState.showCountBadge
                  })
              }
            }
          }

          // Picker icon: one bordered button per glyph, the current one
          // highlighted via the kit Button's `selected` state.
          BorderSurface {
            id: glyphRowCard
            width: parent.width
            // Size to the whole content column (title + sheet + caption),
            // not just the glyph row — otherwise the Native centering lets
            // the taller column spill over the card above and its own
            // bottom edge.
            implicitHeight: glyphCardContent.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            // Same card treatment as the count-badge row: normal border at
            // rest, hover-cursor border under the mouse. Palette follows
            // the bar foreground like the row above it.
            color: Style.controlFill(false, glyphCardHover.containsMouse, root.barForeground, Color.accent)
            borderSpec: Border.controlSpec(glyphCardHover.containsMouse ? "hover-cursor" : "normal", root.barForeground, Color.accent)
            Behavior on color { ColorAnimation { duration: 100 } }

            MouseArea {
              id: glyphCardHover
              // Hover/sensor only, below the buttons card-owning click
              // pattern lives on the glyph buttons themselves.
              anchors.fill: parent
              hoverEnabled: true
            }

            Column {
              id: glyphCardContent
              width: parent.width
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                width: parent.width
                leftPadding: Style.spacing.rowPaddingX
                text: "Picker icon"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Row {
                id: glyphRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(6)

                Repeater {
                  model: BH.OptionGlyphs.choices

                  Button {
                    required property var modelData
                    // Icon slot, not the text slot: the kit bolds and
                    // remetricizes `text` when selected, which mis-centers
                    // a Nerd Font glyph; `iconText` renders like every
                    // other icon in the kit.
                    iconText: modelData.glyph
                    iconSize: Style.font.icon
                    selected: BH.BarHideState.pickerGlyph === modelData.glyph
                    tooltipText: "Bar Hide: use " + modelData.name
                    bordered: true
                    focusable: false
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    // Uniform square sheet: content-sized buttons take the
                    // metrics of each glyph and go ragged.
                    readonly property real _sheetSize:
                      Style.font.icon + Style.spacing.controlPaddingX * 2
                    implicitWidth: _sheetSize
                    implicitHeight: _sheetSize
                    horizontalPadding: 0
                    onClicked: {
                      if (root.hostWidget && typeof root.hostWidget.applySettings === "function")
                        root.hostWidget.applySettings({
                          pickerGlyph: modelData.glyph
                        })
                    }
                  }
                }
              }

              Text {
                width: parent.width
                leftPadding: Style.spacing.rowPaddingX
                text: "The icon on the bar's picker button."
                color: Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }
  }
}
