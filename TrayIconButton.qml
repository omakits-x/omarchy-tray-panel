// SPDX-License-Identifier: MIT

import QtQuick
import qs.Commons
import "TrayModel.js" as TrayModel

// One clickable tray icon. Used both on the bar (small, bar tooltips, no
// highlight) and inside the overflow panel (larger cell, hover highlight, name
// reported to the panel footer). Menu requests are forwarded as a signal so
// each host decides where the menu is rendered: the bar anchors a PopupCard,
// the panel switches to its own menu view.
Item {
  id: root

  required property var trayItem

  property var bar: null
  property real cellSize: Style.bar.iconSlot
  property real iconSize: Style.space(12)
  property color foreground: bar ? bar.foreground : Color.foreground
  property bool highlighted: false
  property bool interactive: true
  // The bar registers its click targets so a click on the bar while a panel is
  // open is forwarded instead of only dismissing the panel. Panel instances
  // live in another window and must not register.
  property bool barClickTarget: false

  signal menuRequested(var trayItem, var anchor, var mouse)
  signal activated()
  signal hoverChanged(bool hovered)

  readonly property bool hovered: mouseArea.containsMouse
  readonly property string tooltip: TrayModel.trayName(root.trayItem)

  function dispatchPress(button, mouse) {
    var item = root.trayItem
    if (!item) return
    var point = mouse || { x: root.width / 2, y: root.height / 2 }
    if (button === Qt.RightButton) root.menuRequested(item, root, point)
    else if (button === Qt.MiddleButton) item.secondaryActivate()
    else if (item.onlyMenu) root.menuRequested(item, root, point)
    else {
      item.activate()
      root.activated()
    }
  }

  // Called by the bar when a click lands on this item while a panel is open.
  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.dispatchPress(button, null)
  }

  Component.onCompleted: {
    if (root.barClickTarget && root.bar && typeof root.bar.registerClickTarget === "function")
      root.bar.registerClickTarget(root)
  }
  Component.onDestruction: {
    if (root.barClickTarget && root.bar && typeof root.bar.unregisterClickTarget === "function")
      root.bar.unregisterClickTarget(root)
  }

  implicitWidth: root.cellSize
  implicitHeight: root.cellSize

  Rectangle {
    visible: root.highlighted
    anchors.fill: parent
    radius: Math.max(2, Style.cornerRadius)
    color: Style.hoverFillFor(root.foreground, root.foreground)
  }

  TrayIcon {
    anchors.centerIn: parent
    width: root.iconSize
    height: root.iconSize
    icon: root.trayItem ? root.trayItem.icon : ""
    color: root.foreground
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    enabled: root.interactive
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      root.hoverChanged(true)
      if (root.barClickTarget && root.bar) root.bar.showTooltip(root, root.tooltip)
    }
    onExited: {
      root.hoverChanged(false)
      if (root.barClickTarget && root.bar) root.bar.hideTooltip(root)
    }
    onPressed: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.dispatchPress(Qt.RightButton, mouse)
        mouse.accepted = true
      }
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) mouse.accepted = true
      else root.dispatchPress(mouse.button, mouse)
    }
    onWheel: function(wheel) {
      if (root.trayItem) root.trayItem.scroll(wheel.angleDelta.y, false)
    }
  }
}
