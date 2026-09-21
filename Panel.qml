// SPDX-License-Identifier: MIT
//
// The overflow panel: a Windows-style flyout holding the tray icons the user
// hid from the bar, plus the settings view that decides which icons those are.
//
// Three views share one KeyboardPanel surface:
//
//   icons     hidden tray icons in a grid (default; left click on the chevron)
//   settings  every tray icon with a show/hide switch (right click on the chevron)
//   menu      the DBusMenu of a tray icon, rendered in place (right click on an icon)
//
// Menus requested from inside the panel are rendered here rather than as a
// PopupCard because the panel is its own layer-shell window: a PopupCard anchors
// through QsWindow of the anchor item, which cannot cross window boundaries.

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "I18n.js" as I18n
import "TrayModel.js" as TrayModel

Panel {
  id: root
  moduleName: "io.github.omakitsx.tray-panel"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string view: "icons"
  property var menuTrayItem: null
  property int cursor: -1
  property string hoverName: ""
  // Set by the menu view so the panel can forward key handling into the menu.
  property var menuList: null

  // --------------------------------------------------------------- settings

  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  // Share the bar widget's partition instead of recomputing it: that side
  // already owns the dropbox-ownership cache, and one source keeps the two
  // surfaces in step.
  readonly property var trayState: root.hostWidget && root.hostWidget.trayState
    ? root.hostWidget.trayState : ({ shown: [], hidden: [], all: [] })
  readonly property var hiddenItems: root.trayState.hidden
  readonly property var allItems: root.trayState.all

  readonly property string language: I18n.resolveLanguage(root.setting("language", "auto"), Qt.locale().name)

  function tr(key) {
    return I18n.text(root.language, key)
  }

  readonly property color contentForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string contentFontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // The settings rows put their option chips behind a caption column, and how
  // wide that column has to be is a property of the language: "Panel position"
  // needs about half again the room of "面板位置". A hard-coded column let the
  // English captions run out of their box and paint underneath the chips, so
  // the captions are measured instead and handed to each OptionRow.
  //
  // The probes live at the panel root because the settings view is a lazily
  // instantiated Component, and the card width below needs the number before
  // that view exists.
  TextMetrics {
    id: placementLabelMetrics
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.caption
    text: root.tr("panel.placement")
  }

  TextMetrics {
    id: barPositionLabelMetrics
    font: placementLabelMetrics.font
    text: root.tr("panel.barPosition")
  }

  TextMetrics {
    id: revealLabelMetrics
    font: placementLabelMetrics.font
    text: root.tr("panel.revealOnAttention")
  }

  TextMetrics {
    id: languageLabelMetrics
    font: placementLabelMetrics.font
    text: root.tr("panel.language")
  }

  // Floor, not target: Chinese never grew past the column it has always had,
  // so its layout is untouched.
  readonly property real settingsLabelMinWidth: Style.space(56)
  readonly property real settingsLabelWidth: Math.max(settingsLabelMinWidth,
    placementLabelMetrics.width,
    barPositionLabelMetrics.width,
    revealLabelMetrics.width,
    languageLabelMetrics.width)


  readonly property int gridColumns: 5
  readonly property real cellSize: Style.space(44)
  readonly property real rowsCap: Math.max(Style.space(120), panel.availableCardHeight - panel.verticalContentInset)

  // -------------------------------------------------------------- lifecycle

  function openView(name) {
    root.view = String(name || "icons")
    root.cursor = -1
    root.hoverName = ""
    root.controller.show()
  }

  function open() {
    root.openView("icons")
  }

  function close() {
    root.menuList = null
    root.menuTrayItem = null
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    root.close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  // ------------------------------------------------------- tray item actions

  // Every mutation goes back through the bar widget: it owns the inline
  // shell.json entry and the optimistic local update that keeps the bar and the
  // panel in step until the shell reloads the file.
  function toggleHidden(id) {
    if (root.hostWidget && typeof root.hostWidget.toggleHidden === "function") root.hostWidget.toggleHidden(id)
  }

  function setHidden(id, hidden) {
    if (root.hostWidget && typeof root.hostWidget.setHidden === "function") root.hostWidget.setHidden(id, hidden)
  }

  function hideAll() {
    if (root.hostWidget && typeof root.hostWidget.hideAll === "function") root.hostWidget.hideAll()
  }

  function showAll() {
    if (root.hostWidget && typeof root.hostWidget.showAll === "function") root.hostWidget.showAll()
  }

  function setLanguage(value) {
    if (root.hostWidget && typeof root.hostWidget.setLanguage === "function") root.hostWidget.setLanguage(value)
  }

  function setPanelPlacement(value) {
    if (root.hostWidget && typeof root.hostWidget.setPanelPlacement === "function")
      root.hostWidget.setPanelPlacement(value)
  }

  function setBarSection(value) {
    if (root.hostWidget && typeof root.hostWidget.setBarSection === "function")
      root.hostWidget.setBarSection(value)
  }

  function setRevealOnAttention(value) {
    if (root.hostWidget && typeof root.hostWidget.setRevealOnAttention === "function")
      root.hostWidget.setRevealOnAttention(value)
  }

  readonly property bool revealOnAttention: root.setting("revealOnAttention", true) === true

  readonly property string barSection: root.hostWidget ? String(root.hostWidget.barSection || "") : ""

  function itemHidden(id) {
    return TrayModel.isHidden(root.hiddenIds, id)
  }

  // ------------------------------------------------------------- interaction

  function requestMenu(item) {
    if (!item || !item.menu) return
    root.menuTrayItem = item
    root.view = "menu"
    root.cursor = -1
    root.hoverName = ""
  }

  function leaveMenu() {
    root.view = "icons"
    root.cursor = -1
    root.menuTrayItem = null
  }

  // ---------------------------------------------------------------- keyboard

  function moveCursor(dx, dy) {
    if (root.view === "menu") {
      if (root.menuList && typeof root.menuList.moveCursor === "function")
        root.menuList.moveCursor(dy !== 0 ? dy : (dx >= 0 ? 1 : -1))
      return
    }
    var list = root.view === "icons" ? root.hiddenItems : root.allItems
    if (!list.length) return
    var columns = root.view === "icons" ? root.gridColumns : 1
    if (root.cursor < 0) {
      root.cursor = 0
      return
    }
    var next = root.cursor
    if (dy !== 0) next = root.cursor + dy * columns
    else if (dx !== 0) next = root.cursor + dx
    if (next < 0) next = 0
    if (next >= list.length) next = list.length - 1
    root.cursor = next
  }

  function activateCursor() {
    if (root.view === "menu") {
      if (root.menuList && typeof root.menuList.activateCursor === "function") root.menuList.activateCursor()
      return
    }
    var list = root.view === "icons" ? root.hiddenItems : root.allItems
    if (root.cursor < 0 || root.cursor >= list.length) return
    var item = list[root.cursor]
    if (root.view === "icons") {
      if (item.onlyMenu) root.requestMenu(item)
      else {
        item.activate()
        root.close()
      }
      return
    }
    root.toggleHidden(TrayModel.trayId(item))
  }

  function handleTextKey(text) {
    if (text === "s") {
      root.view = root.view === "settings" ? "icons" : "settings"
      root.cursor = -1
    } else if (text === "a") {
      root.showAll()
    } else if (text === "h") {
      root.hideAll()
    }
  }

  // ------------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Where the card lands: under the chevron that opened it, or centred on
    // the screen. KeyboardPanel supports exactly these two.
    centerOnBar: root.setting("panelPlacement", "button") === "center"
    // The settings view is a form: its rows need room for a caption column
    // beside the option chips, which the 260px icon grid does not. The card
    // still grows if a language asks for a wider caption column than the base
    // width already reserves.
    contentWidth: panel.fittedContentWidth(root.view === "settings"
      ? Style.space(390) + Math.max(0, root.settingsLabelWidth - root.settingsLabelMinWidth)
      : Style.space(260))
    // No fixed height cap: the settings view sizes its icon list to whatever
    // room is left over (settingsRoot.listCap), so the card is only ever as
    // tall as the screen allows it to be.
    contentHeight: panel.fittedContentHeight(
      viewLoader.item ? viewLoader.item.implicitHeight : Style.space(120))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(text) { root.handleTextKey(text) }

      Loader {
        id: viewLoader
        width: parent.width
        sourceComponent: root.view === "icons" ? iconsView
          : (root.view === "settings" ? settingsView : menuView)
      }
    }
  }

  // ------------------------------------------------------------- icons view

  Component {
    id: iconsView

    Column {
      id: iconsRoot
      width: parent.width
      spacing: Style.space(8)

      Item {
        id: iconsHeader
        width: iconsRoot.width
        implicitHeight: Style.space(24)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          text: root.tr("panel.hidden.title")
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Button {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          text: root.tr("panel.action.settings")
          iconText: "\uf013"
          foreground: root.contentForeground
          fontSize: Style.font.bodySmall
          iconSize: Style.font.bodySmall
          horizontalPadding: 8
          verticalPadding: 3
          onClicked: {
            root.view = "settings"
            root.cursor = -1
          }
        }
      }

      Item {
        id: gridBox
        width: iconsRoot.width
        implicitHeight: root.hiddenItems.length > 0
          ? Math.min(grid.implicitHeight, root.rowsCap)
          : emptyLabel.implicitHeight

        ScrollHint {
          flickable: gridFlick
          foreground: root.contentForeground
        }

        Flickable {
          id: gridFlick
          anchors.fill: parent
          visible: root.hiddenItems.length > 0
          contentWidth: width
          contentHeight: grid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height

          // A real, draggable scrollbar. QtQuick.Controls does resolve inside
          // a user plugin — the earlier "ScrollBar is not a type" failures were
          // a stale QML disk cache replaying a broken first compile.
          ScrollBar.vertical: ScrollBar {
            id: gridScroll
            policy: ScrollBar.AsNeeded
            width: Style.space(5)
            padding: 0

            contentItem: Rectangle {
              implicitWidth: Style.space(5)
              radius: width / 2
              color: root.contentForeground
              opacity: gridScroll.pressed ? 0.9 : (gridScroll.active ? 0.65 : 0.35)
            }

            background: Item {}
          }

          Grid {
            id: grid
            width: gridFlick.width - (gridScroll.visible ? Style.space(7) : 0)
            columns: root.gridColumns
            spacing: 0

            Repeater {
              model: root.hiddenItems

              TrayIconButton {
                id: cell
                required property var modelData
                required property int index
                trayItem: modelData
                bar: root.bar
                cellSize: root.cellSize
                iconSize: Style.space(20)
                foreground: root.contentForeground
                highlighted: cell.hovered || root.cursor === index
                onMenuRequested: function(item) { root.requestMenu(item) }
                onActivated: root.close()
                onHoverChanged: function(hovered) { root.hoverName = hovered ? cell.tooltip : "" }
              }
            }
          }
        }

        Text {
          id: emptyLabel
          visible: root.hiddenItems.length === 0
          width: parent.width
          text: root.tr("panel.hidden.empty")
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }

      Text {
        id: iconsFooter
        width: iconsRoot.width
        height: Style.space(16)
        text: root.hoverName
        color: Qt.darker(root.contentForeground, 1.3)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  // ---------------------------------------------------------- settings view

  Component {
    id: settingsView

    Column {
      id: settingsRoot
      width: parent.width
      spacing: Style.space(8)

      // Everything below the icon list, plus the header above it. The list is
      // the only part that scrolls, so it is the part that has to give when the
      // card runs out of room — otherwise a long tray pushes the Done button
      // off the bottom of the card and it can never be reached.
      readonly property real listCap: {
        var chrome = settingsHeader.implicitHeight + settingsHint.implicitHeight
          + onBarHeader.implicitHeight + listActions.implicitHeight + settingsFooter.implicitHeight
          + settingsRoot.spacing * 5
        return Math.max(Style.space(96),
          panel.availableCardHeight - panel.verticalContentInset - chrome)
      }

      Item {
        id: settingsHeader
        width: settingsRoot.width
        implicitHeight: Style.space(24)

        Button {
          id: settingsBack
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          text: root.tr("panel.action.back")
          iconText: "\u2039"
          foreground: root.contentForeground
          fontSize: Style.font.bodySmall
          iconSize: Style.font.bodySmall
          horizontalPadding: 8
          verticalPadding: 3
          onClicked: {
            root.view = "icons"
            root.cursor = -1
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: settingsBack.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          text: root.tr("panel.settings.title")
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
      }

      Text {
        id: settingsHint
        width: settingsRoot.width
        text: root.tr("panel.settings.hint")
        color: Qt.darker(root.contentForeground, 1.4)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Item {
        id: onBarHeader
        width: settingsRoot.width
        implicitHeight: onBarTitle.implicitHeight

        PanelSectionHeader {
          id: onBarTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.tr("panel.section.bar")
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: I18n.format(root.language, "panel.count", {
            shown: root.trayState.shown ? root.trayState.shown.length : 0,
            hidden: root.hiddenItems.length
          })
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        id: listBox
        width: settingsRoot.width
        implicitHeight: root.allItems.length > 0
          ? Math.min(list.implicitHeight, settingsRoot.listCap)
          : trayEmptyLabel.implicitHeight

        ScrollHint {
          flickable: listFlick
          foreground: root.contentForeground
        }

        Flickable {
          id: listFlick
          anchors.fill: parent
          visible: root.allItems.length > 0
          contentWidth: width
          contentHeight: list.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height

          // AsNeeded: while every icon fits there is no scrollbar at all, so a
          // short list looks exactly as it did before.
          ScrollBar.vertical: ScrollBar {
            id: listScroll
            policy: ScrollBar.AsNeeded
            width: Style.space(5)
            padding: 0

            contentItem: Rectangle {
              implicitWidth: Style.space(5)
              radius: width / 2
              color: root.contentForeground
              opacity: listScroll.pressed ? 0.9 : (listScroll.active ? 0.65 : 0.35)
            }

            background: Item {}
          }

          Column {
            id: list
            width: listFlick.width - (listScroll.visible ? Style.space(7) : 0)
            spacing: 0

            Repeater {
              model: root.allItems

              delegate: Item {
                id: row
                required property var modelData
                required property int index

                readonly property string itemId: TrayModel.trayId(modelData)
                readonly property bool itemHidden: root.itemHidden(row.itemId)
                readonly property bool selected: root.cursor === index

                width: list.width
                implicitHeight: Style.space(32)

                Rectangle {
                  anchors.fill: parent
                  radius: Math.max(2, Style.cornerRadius)
                  color: (rowMouse.containsMouse || row.selected)
                    ? Style.hoverFillFor(root.contentForeground, root.contentForeground) : "transparent"
                }

                TrayIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  width: Style.space(16)
                  height: Style.space(16)
                  icon: row.modelData.icon
                  color: root.contentForeground
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(30)
                  anchors.right: rowToggle.left
                  anchors.rightMargin: Style.space(8)
                  text: TrayModel.trayName(row.modelData)
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                // A segmented pair rather than one button. A lone button
                // labelled with the *action* reads as the current state, so
                // icons that were already hidden showed "Show" and looked
                // inverted. Two options with the live one highlighted say it
                // plainly — and it is the same OptionRow the settings footer
                // uses, minus the caption.
                OptionRow {
                  id: rowToggle
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  options: [
                    { label: root.tr("panel.action.show"), value: "shown" },
                    { label: root.tr("panel.action.hide"), value: "hidden" }
                  ]
                  value: row.itemHidden ? "hidden" : "shown"
                  fontSize: Style.font.bodySmall
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onSelected: function(value) { root.setHidden(row.itemId, value === "hidden") }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  anchors.rightMargin: rowToggle.width + Style.space(8)
                  hoverEnabled: true
                  onClicked: root.toggleHidden(row.itemId)
                }
              }
            }
          }
        }

        Text {
          id: trayEmptyLabel
          visible: root.allItems.length === 0
          width: parent.width
          text: root.tr("panel.tray.empty")
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }

      Row {
        id: listActions
        width: settingsRoot.width
        spacing: Style.space(8)

        Button {
          width: (parent.width - parent.spacing) / 2
          text: root.tr("panel.action.showAll")
          bordered: true
          foreground: root.contentForeground
          fontSize: Style.font.bodySmall
          verticalPadding: 4
          onClicked: root.showAll()
        }

        Button {
          width: (parent.width - parent.spacing) / 2
          text: root.tr("panel.action.hideAll")
          bordered: true
          foreground: root.contentForeground
          fontSize: Style.font.bodySmall
          verticalPadding: 4
          onClicked: root.hideAll()
        }
      }

      Column {
        id: settingsFooter
        width: settingsRoot.width
        spacing: Style.space(8)

        PanelSeparator { foreground: root.contentForeground }

        PanelSectionHeader {
          text: root.tr("panel.section.panel")
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        OptionRow {
          label: root.tr("panel.placement")
          labelWidth: root.settingsLabelWidth
          options: [
            { label: root.tr("panel.placement.button"), value: "button" },
            { label: root.tr("panel.placement.left"), value: "left" },
            { label: root.tr("panel.placement.center"), value: "center" },
            { label: root.tr("panel.placement.right"), value: "right" }
          ]
          value: String(root.setting("panelPlacement", "button"))
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onSelected: function(value) { root.setPanelPlacement(value) }
        }

        OptionRow {
          label: root.tr("panel.barPosition")
          labelWidth: root.settingsLabelWidth
          options: [
            { label: root.tr("panel.placement.left"), value: "left" },
            { label: root.tr("panel.placement.center"), value: "center" },
            { label: root.tr("panel.placement.right"), value: "right" }
          ]
          value: root.barSection
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onSelected: function(value) { root.setBarSection(value) }
        }

        // A switch, not another pair of chips: this one is a plain on/off, and
        // the labeled Toggle row keeps its label on the left and its switch on
        // the right however long the language makes the label.
        Toggle {
          width: settingsRoot.width
          label: root.tr("panel.revealOnAttention")
          description: root.tr("panel.revealOnAttention.description")
          checked: root.revealOnAttention
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setRevealOnAttention(!root.revealOnAttention)
        }

        PanelSeparator { foreground: root.contentForeground }

        PanelSectionHeader {
          text: root.tr("panel.section.language")
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        OptionRow {
          label: root.tr("panel.language")
          labelWidth: root.settingsLabelWidth
          options: [
            { label: root.tr("panel.language.auto"), value: "auto" },
            { label: "EN", value: "en" },
            { label: "\u4e2d\u6587", value: "zh" }
          ]
          value: String(root.setting("language", "auto"))
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onSelected: function(value) { root.setLanguage(value) }
        }

        Button {
          width: settingsRoot.width
          text: root.tr("panel.action.done")
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.bodySmall
          verticalPadding: 4
          onClicked: root.close()
        }
      }
    }
  }

  // -------------------------------------------------------------- menu view

  Component {
    id: menuView

    Column {
      id: menuRoot
      width: parent.width
      spacing: Style.space(8)

      Item {
        id: menuHeader
        width: menuRoot.width
        implicitHeight: Style.space(24)

        Button {
          id: menuBack
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          text: root.tr("panel.action.back")
          iconText: "\u2039"
          foreground: root.contentForeground
          fontSize: Style.font.bodySmall
          iconSize: Style.font.bodySmall
          horizontalPadding: 8
          verticalPadding: 3
          onClicked: root.leaveMenu()
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: menuBack.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          text: root.menuTrayItem ? TrayModel.trayName(root.menuTrayItem) : ""
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
      }

      TrayMenuList {
        id: panelMenuList
        width: menuRoot.width
        menuHandle: root.menuTrayItem ? root.menuTrayItem.menu : null
        menuTitle: root.menuTrayItem ? TrayModel.trayName(root.menuTrayItem) : ""
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        maxRowsHeight: root.rowsCap
        keyboardCursor: true
        cursor: root.cursor
        onItemTriggered: root.close()
        onCursorMoved: function(index) { root.cursor = index }

        Component.onCompleted: root.menuList = panelMenuList
        Component.onDestruction: if (root.menuList === panelMenuList) root.menuList = null
      }
    }
  }
}
