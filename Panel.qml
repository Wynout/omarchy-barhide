import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar Hide's screen picker popup. Lists every connected screen with its
// identity, and toggles which of them carry the bar. Settings persist in the
// picker's own bar.layout entry via updateEntryInline, which is the same
// write path the built-in clock uses for its format cycling.
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

  // On/off switch for one screen's bar. The caller owns the value — binds
  // `checked` to the effective bar state and flips it via `onToggled` — the
  // same stateless pattern Ui.Toggle and Ui.ToggleSwitch are built around.
  component ScreenToggle: ToggleSwitch {
    id: screenToggleRoot

    signal activated()

    checked: false
    onToggled: screenToggleRoot.activated()
  }

  // Small text button for actions that aren't on/off (forget, show on all).
  component RoleButton: Rectangle {
    id: roleButton

    property string label: ""
    property bool highlighted: false

    signal activated()

    implicitWidth: labelMeter.implicitWidth + Style.space(14)
    implicitHeight: Style.space(20)
    radius: Style.cornerRadius
    opacity: enabled ? 1.0 : 0.4
    color: roleMouse.containsMouse || highlighted ? Style.selectedFill : Style.normalFill
    border.width: 1
    border.color: highlighted ? Style.selectedBorderColor : Style.normalBorderColor

    Text {
      id: labelMeter
      anchors.centerIn: parent
      text: roleButton.label
      color: roleButton.highlighted ? Color.accent : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: roleMouse
      anchors.fill: parent
      enabled: roleButton.enabled
      hoverEnabled: roleButton.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: roleButton.activated()
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

        // ---- Hero: title · mode read-out
        Text {
          width: parent.width
          text: "Bar Hide"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          width: parent.width
          text: root.resolvedTargets.length
            ? "Bar on: " + root.resolvedTargets.map(function(s) { return s.name }).join(", ")
            : (root.selectedRefs.length
                ? "Nothing hidden is connected - bar on every screen."
                : "Bar on every screen - hide one to pin the rest.")
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {}

        // ---- Connected screens
        Repeater {
          model: Quickshell.screens

          delegate: Column {
            id: screenRow

            required property var modelData

            readonly property bool onBar: root.onBarNow(modelData)

            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(nameText.implicitHeight, screenToggle.implicitHeight)

              Column {
                id: nameText
                anchors.left: parent.left
                anchors.right: screenToggle.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  text: screenRow.modelData.name
                    + (screenRow.onBar ? " - bar enabled" : "")
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: screenRow.onBar
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  text: screenRow.modelData.model || "unknown model"
                  color: Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              ScreenToggle {
                id: screenToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: screenRow.onBar
                onActivated: root.toggleScreen(screenRow.modelData)
              }
            }
          }
        }

        // ---- Selected but not connected: they keep their place in the
        // list until their monitor returns, but can be forgotten here.
        Repeater {
          model: root.unresolvedRefs

          delegate: Row {
            id: unresolvedRow

            required property var modelData

            width: parent.width
            spacing: Style.space(8)

            Text {
              text: unresolvedRow.modelData.name
                ? unresolvedRow.modelData.name + " (not connected)"
                : "not connected"
              color: Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
            }

            RoleButton {
              label: "forget"
              onActivated: root.forgetRef(unresolvedRow.modelData)
            }          }
        }

        PanelSeparator {}

        // ---- Selection read-out + clear
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

        Row {
          spacing: Style.space(6)

          RoleButton {
            label: "show on all"
            enabled: root.selectedRefs.length > 0
            onActivated: root.clearAll()
          }
        }

        Text {
          width: parent.width
          text: "Nothing hidden (or none of it connected) - the bar shows on every screen."
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
