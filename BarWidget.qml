// SPDX-License-Identifier: MIT
//
// Tray Panel — system tray icons on the bar plus a Windows-style overflow
// panel for the icons you hide.
//
// Layout on the bar:
//
//     [icon] [icon] ... [chevron]
//
// The chevron is always present so there is a stable way into both surfaces:
// left click opens the overflow panel (hidden icons), right click opens the
// same panel straight on its settings view.
//
// Settings live inline in this widget's shell.json entry:
//
//     { "id": "io.github.omakitsx.tray-panel", "hidden": ["id-a"], "language": "auto" }
//
// `hidden` lists tray item ids that move into the overflow panel; every other
// item stays on the bar. `language` is "auto" (follow the locale), "en" or "zh".

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "I18n.js" as I18n
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "io.github.omakitsx.tray-panel"

  // --------------------------------------------------------------- settings

  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property string language: I18n.resolveLanguage(setting("language", "auto"), Qt.locale().name)

  function tr(key) {
    return I18n.text(root.language, key)
  }

  // ----------------------------------------------------------- tray contents

  // Only Dropbox ownership is read out of the bar layout, and it is cached as a
  // boolean. Reading `bar.layoutConfig` inside the trayState binding formed a
  // loop: partition -> new arrays -> the Repeater rebuilds its icon buttons ->
  // their click targets register -> the bar re-syncs -> layoutConfig is replaced
  // with a fresh object -> partition runs again. A boolean keeps the binding
  // stable, because an unchanged value never notifies.
  property bool ownsDropbox: false
  readonly property var trayState: TrayModel.partition(
    SystemTray.items.values,
    root.hiddenIds,
    root.ownsDropbox,
    Status.Passive)

  function syncLayoutOwnership() {
    root.ownsDropbox = TrayModel.layoutHasWidget(
      root.bar ? root.bar.layoutConfig : null, "omarchy.dropbox")
  }

  Connections {
    target: root.bar
    function onLayoutConfigChanged() {
      root.syncLayoutOwnership()
      root.refreshBarSection()
    }
  }
  readonly property var shownItems: root.trayState.shown
  readonly property var hiddenItems: root.trayState.hidden
  readonly property var allItems: root.trayState.all

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int trayItemExtent: Style.bar.iconSlot

  // Chevron points at the edge the panel opens from, so it reads the same way
  // on every bar position.
  readonly property int overflowRotation: {
    var position = root.bar ? String(root.bar.position || "top") : "top"
    if (position === "bottom") return 180
    if (position === "left") return -90
    if (position === "right") return 90
    return 0
  }

  // ------------------------------------------------------------ persistence

  // Merge into the existing entry instead of replacing it: updateEntryInline
  // rewrites the whole layout entry from what it is handed, so anything not
  // copied here would be dropped from shell.json.
  function persist(values) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var next in values) entry[next] = values[next]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setHidden(id, hidden) {
    root.persist({ hidden: TrayModel.withHidden(root.hiddenIds, id, hidden) })
  }

  function toggleHidden(id) {
    root.persist({ hidden: TrayModel.toggleHidden(root.hiddenIds, id) })
  }

  function hideAll() {
    root.persist({ hidden: TrayModel.hiddenUnion(root.hiddenIds, root.allItems) })
  }

  function showAll() {
    root.persist({ hidden: [] })
  }

  function setLanguage(value) {
    root.persist({ language: String(value || "auto") })
  }

  function setPanelPlacement(value) {
    root.persist({ panelPlacement: String(value || "button") })
  }

  // ------------------------------------------------------------------ panel

  // Where the overflow panel appears. "button" follows the chevron that opened
  // it; the others park an invisible zero-size anchor at the screen edge or
  // centre - KeyboardPanel centres the card on its anchorItem and then clamps
  // it into the screen, which lands the card exactly where it should be.
  readonly property string panelPlacement: String(root.setting("panelPlacement", "button"))
  readonly property var panelAnchor: root.panelPlacement === "button" ? root.overflowAnchor : placementAnchor

  function updatePlacementAnchor() {
    var placement = root.panelPlacement
    if (placement === "button") return
    var window = root.QsWindow ? root.QsWindow.window : null
    if (!window) return
    var own = root.mapToItem(null, 0, 0)
    if (root.vertical) {
      var targetY = placement === "left" ? 0 : (placement === "right" ? window.height : window.height / 2)
      placementAnchor.x = 0
      placementAnchor.y = targetY - own.y
    } else {
      var targetX = placement === "left" ? 0 : (placement === "right" ? window.width : window.width / 2)
      placementAnchor.x = targetX - own.x
      placementAnchor.y = 0
    }
  }

  Item {
    id: placementAnchor
    visible: false
    width: 0
    height: 0
  }

  // Which bar section this widget currently sits in, and how to move it. The
  // bar belongs to the shell, and a bar-widget has no bar capabilities (only a
  // full "bar" kind plugin does), so mutateShellConfig is not available here.
  // Moving through the official CLI keeps shell.json exactly as
  // "omarchy bar move" would write it by hand.
  property string barSection: ""

  function refreshBarSection() {
    var layout = root.bar ? root.bar.layoutConfig : null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = TrayModel.asList(layout && layout[sections[s]])
      for (var i = 0; i < entries.length; i++) {
        if (TrayModel.entryId(entries[i]) === root.moduleName) {
          root.barSection = sections[s]
          return
        }
      }
    }
    root.barSection = ""
  }

  function setBarSection(section) {
    var target = String(section || "")
    if (["left", "center", "right"].indexOf(target) === -1) return
    if (target === root.barSection) return
    moveProcess.targetSection = target
    moveProcess.running = true
  }

  Process {
    id: moveProcess
    property string targetSection: ""
    command: ["omarchy", "bar", "move", root.moduleName, "--section", targetSection]
    running: false
    onExited: root.refreshBarSection()
  }

  readonly property bool panelOpen: panelLoader.item ? panelLoader.item.opened === true : false
  // The bar host looks for open()/close()/opened to treat a widget as a panel
  // and include it in panel tab navigation.
  readonly property bool opened: root.panelOpen
  readonly property var overflowAnchor: trayContent.item && trayContent.item.overflowButton
    ? trayContent.item.overflowButton : root

  function openPanel(view) {
    var panel = panelLoader.item
    if (!panel) return
    var target = String(view || "icons")
    if (root.panelOpen) {
      // Already open: a second press on the same view closes it, a press on the
      // other view switches to it.
      if (panel.view === target) root.close()
      else panel.view = target
      return
    }
    if (root.menuOpen) root.closeMenu()
    root.updatePlacementAnchor()
    panel.openView(target)
  }

  function open() {
    root.openPanel("icons")
  }

  function close() {
    root.menuOpen = false
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.panelOpen) root.close()
    else root.openPanel("icons")
  }

  function closeForPopoutSwitch() {
    root.menuOpen = false
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root.panelAnchor
    if ("hostWidget" in target) target.hostWidget = root
  }

  Component.onCompleted: {
    root.syncLayoutOwnership()
    root.refreshBarSection()
  }
  onBarChanged: {
    root.syncLayoutOwnership()
    root.refreshBarSection()
    root.injectPanel()
  }
  onSettingsChanged: root.injectPanel()
  onPanelAnchorChanged: root.injectPanel()

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

  // ------------------------------------------------------------- bar menu

  // Tray menus opened from the bar itself stay anchored to the icon that was
  // clicked, which is what users expect from a tray. Menus requested from
  // inside the overflow panel are rendered by the panel instead, because a
  // PopupCard cannot anchor to an item living in another window.
  property bool menuOpen: false
  property var menuItem: null
  property var menuAnchor: null

  function openMenu(item, anchor, mouse) {
    if (!item) return
    if (!item.menu) {
      // No DBusMenu handle. `display()` is the only remaining path; the shell
      // does not run in QApplication mode, so most apps will no-op here, but a
      // tray item with neither a menu nor an activation has nothing else.
      if (anchor && anchor.QsWindow && mouse) {
        var point = anchor.QsWindow.contentItem.mapFromItem(anchor, mouse.x, mouse.y)
        item.display(anchor.QsWindow.window, point.x, point.y)
      }
      return
    }
    // The panel and this menu share one popout coordinator key (this widget),
    // so the bar host will not close one when the other opens — do it here.
    if (root.panelOpen) root.close()
    trayMenuList.reset()
    root.menuItem = item
    root.menuAnchor = anchor || root.overflowAnchor
    root.menuOpen = true
  }

  function closeMenu() {
    root.menuOpen = false
  }

  visible: root.shownItems.length > 0 || root.hiddenItems.length > 0
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Row {
      id: horizontalRow
      readonly property alias overflowButton: overflowButtonItem
      spacing: 0

      Repeater {
        model: root.shownItems

        TrayIconButton {
          required property var modelData
          trayItem: modelData
          bar: root.bar
          barClickTarget: true
          cellSize: root.trayItemExtent
          iconSize: Style.space(12)
          foreground: root.foreground
          onMenuRequested: function(item, anchor, mouse) { root.openMenu(item, anchor, mouse) }
          onActivated: if (root.panelOpen) root.close()
        }
      }

      BarIconButton {
        id: overflowButtonItem
        bar: root.bar
        text: "\uf078"
        textRotation: root.overflowRotation
        tooltipText: root.hiddenItems.length > 0 ? root.tr("bar.hidden") : root.tr("bar.settings")
        onPressed: function(button) {
          if (button === Qt.RightButton) root.openPanel("settings")
          else root.openPanel("icons")
        }
      }
    }
  }

  Component {
    id: verticalTray

    Column {
      id: verticalColumn
      readonly property alias overflowButton: overflowButtonItem
      spacing: 0

      Repeater {
        model: root.shownItems

        TrayIconButton {
          required property var modelData
          trayItem: modelData
          bar: root.bar
          barClickTarget: true
          cellSize: root.trayItemExtent
          iconSize: Style.space(12)
          foreground: root.foreground
          onMenuRequested: function(item, anchor, mouse) { root.openMenu(item, anchor, mouse) }
          onActivated: if (root.panelOpen) root.close()
        }
      }

      BarIconButton {
        id: overflowButtonItem
        bar: root.bar
        text: "\uf078"
        textRotation: root.overflowRotation
        tooltipText: root.hiddenItems.length > 0 ? root.tr("bar.hidden") : root.tr("bar.settings")
        onPressed: function(button) {
          if (button === Qt.RightButton) root.openPanel("settings")
          else root.openPanel("icons")
        }
      }
    }
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.menuAnchor || root
    owner: root
    bar: root.bar
    open: root.menuOpen
    // The card fades out over 140ms (visible stays true for that whole time —
    // see PopupCard's own visible: open || card.opacity > 0), so resetting on
    // "open" would swap a live submenu for the root menu mid-fade. Wait for the
    // fade to actually finish; switching to a different tray item still resets
    // immediately, from openMenu() itself.
    onVisibleChanged: if (!visible) trayMenuList.reset()
    padding: Style.space(8)
    borderColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(trayMenuList.implicitHeight)

    TrayMenuList {
      id: trayMenuList
      anchors.fill: parent
      menuHandle: root.menuItem ? root.menuItem.menu : null
      menuTitle: root.menuItem ? TrayModel.trayName(root.menuItem) : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
      maxRowsHeight: Math.max(0, trayMenuPopup.availableCardHeight - trayMenuPopup.verticalContentInset)
      onItemTriggered: root.closeMenu()
    }
  }

}
