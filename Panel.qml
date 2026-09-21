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
    contentWidth: panel.fittedContentWidth(root.view === "settings" ? Style.space(324) : Style.space(260))
    contentHeight: panel.fittedContentHeight(
      viewLoader.item ? viewLoader.item.implicitHeight : Style.space(120), Style.space(460))

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

          Grid {
            id: grid
            width: gridFlick.width
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
        width: settingsRoot.width
        text: root.tr("panel.settings.hint")
        color: Qt.darker(root.contentForeground, 1.4)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Item {
        id: listBox
        width: settingsRoot.width
        implicitHeight: root.allItems.length > 0
          ? Math.min(list.implicitHeight, root.rowsCap)
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

          Column {
            id: list
            width: listFlick.width
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
                // plainly.
                Row {
                  id: rowToggle
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  spacing: Style.space(2)

                  Button {
                    text: root.tr("panel.action.show")
                    selected: !row.itemHidden
                    foreground: root.contentForeground
                    fontSize: Style.font.bodySmall
                    horizontalPadding: 8
                    verticalPadding: 3
                    onClicked: root.setHidden(row.itemId, false)
                  }

                  Button {
                    text: root.tr("panel.action.hide")
                    selected: row.itemHidden
                    foreground: root.contentForeground
                    fontSize: Style.font.bodySmall
                    horizontalPadding: 8
                    verticalPadding: 3
                    onClicked: root.setHidden(row.itemId, true)
                  }
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

      Column {
        id: settingsFooter
        width: settingsRoot.width
        spacing: Style.space(4)

        Row {
          spacing: Style.space(6)

          Button {
            text: root.tr("panel.action.showAll")
            foreground: root.contentForeground
            fontSize: Style.font.bodySmall
            horizontalPadding: 8
            verticalPadding: 3
            onClicked: root.showAll()
          }

          Button {
            text: root.tr("panel.action.hideAll")
            foreground: root.contentForeground
            fontSize: Style.font.bodySmall
            horizontalPadding: 8
            verticalPadding: 3
            onClicked: root.hideAll()
          }
        }

        Row {
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(56)
            text: root.tr("panel.placement")
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: [
              { label: root.tr("panel.placement.button"), value: "button" },
              { label: root.tr("panel.placement.left"), value: "left" },
              { label: root.tr("panel.placement.center"), value: "center" },
              { label: root.tr("panel.placement.right"), value: "right" }
            ]

            Button {
              required property var modelData
              text: modelData.label
              foreground: root.contentForeground
              fontSize: Style.font.caption
              horizontalPadding: 6
              verticalPadding: 2
              selected: root.setting("panelPlacement", "button") === modelData.value
              bordered: true
              onClicked: root.setPanelPlacement(modelData.value)
            }
          }
        }

        Row {
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(56)
            text: root.tr("panel.barPosition")
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: [
              { label: root.tr("panel.placement.left"), value: "left" },
              { label: root.tr("panel.placement.center"), value: "center" },
              { label: root.tr("panel.placement.right"), value: "right" }
            ]

            Button {
              required property var modelData
              text: modelData.label
              foreground: root.contentForeground
              fontSize: Style.font.caption
              horizontalPadding: 6
              verticalPadding: 2
              selected: root.barSection === modelData.value
              bordered: true
              onClicked: root.setBarSection(modelData.value)
            }
          }
        }

        Row {
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(56)
            text: root.tr("panel.revealOnAttention")
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: [
              { label: root.tr("panel.toggle.on"), value: true },
              { label: root.tr("panel.toggle.off"), value: false }
            ]

            Button {
              required property var modelData
              text: modelData.label
              foreground: root.contentForeground
              fontSize: Style.font.caption
              horizontalPadding: 6
              verticalPadding: 2
              selected: root.revealOnAttention === modelData.value
              bordered: true
              onClicked: root.setRevealOnAttention(modelData.value)
            }
          }
        }

        Row {
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(56)
            text: root.tr("panel.language")
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: [
              { label: root.tr("panel.language.auto"), value: "auto" },
              { label: "EN", value: "en" },
              { label: "\u4e2d\u6587", value: "zh" }
            ]

            Button {
              required property var modelData
              text: modelData.label
              foreground: root.contentForeground
              fontSize: Style.font.caption
              horizontalPadding: 6
              verticalPadding: 2
              selected: root.setting("language", "auto") === modelData.value
              bordered: true
              onClicked: root.setLanguage(modelData.value)
            }
          }
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
