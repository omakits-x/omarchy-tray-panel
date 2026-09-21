// SPDX-License-Identifier: MIT
//
// Renders one level of a StatusNotifierItem menu and drills into submenus.
//
// QsMenuEntry.display() renders a *platform* menu, which Quickshell refuses
// unless the shell root sets `//@ pragma UseQApplication` — omarchy's shell.qml
// does not, so every submenu click would be a silent no-op and apps whose whole
// UI is submenus (e.g. radiotray-ng's station list) would be unusable.
// QsMenuEntry inherits QsMenuHandle, so a child entry can feed a nested
// QsMenuOpener and render inside this item instead of going through the
// platform. Each level keeps its own live opener: a child entry is owned by its
// parent opener's model, so collapsing the stack to a single opener would
// destroy the very entry being displayed (submenu turns up empty).
//
// The host owns the surface (a PopupCard on the bar, or a view inside the
// overflow panel) and just embeds this item, sizing it through maxRowsHeight.

import Quickshell
import QtQuick
import qs.Commons

Item {
  id: root

  required property var menuHandle
  property string menuTitle: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // Cap for the scrollable rows area. 0 means "no cap, size to content".
  property real maxRowsHeight: 0
  property bool keyboardCursor: false
  property int cursor: -1

  // A leaf entry was triggered; the host should close its surface.
  signal itemTriggered()
  signal cursorMoved(int index)

  property var submenuStack: []
  readonly property int depth: root.submenuStack.length
  readonly property string levelTitle: root.depth > 0
    ? String(root.submenuStack[root.depth - 1].title || "") : ""
  readonly property var entries: root.depth > 0
    ? root.submenuStack[root.depth - 1].opener.children
    : rootOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next row
  // lands under a cursor that hasn't moved. A deliberate follow-up click is
  // slower than this window.
  property bool settling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: settleTimer
    interval: 250
    onTriggered: root.settling = false
  }

  function settle() {
    root.settling = true
    settleTimer.restart()
  }

  function reset() {
    root.settling = false
    settleTimer.stop()
    root.cursor = -1
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled would
    // otherwise reopen part-way down with its first entries off screen.
    if (rowsFlick) rowsFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-live
    // child opener references.
    var openers = root.submenuStack
    root.submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) {
      if (openers[i] && openers[i].opener) openers[i].opener.destroy()
    }
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = root.submenuStack.slice()
    stack.push({ opener: opener, title: String(title || "") })
    root.submenuStack = stack
    root.cursor = -1
    root.settle()
  }

  function leaveSubmenu() {
    if (root.submenuStack.length === 0) return
    var stack = root.submenuStack.slice()
    var top = stack.pop()
    root.submenuStack = stack
    root.cursor = -1
    if (top && top.opener) top.opener.destroy()
    root.settle()
  }

  // Both of these only ever describe the root menu; inside a submenu the first
  // rows are real entries and must not be swallowed.
  function rootTitleRow(entry, index) {
    if (root.depth !== 0 || index !== 0 || !entry || !entry.hasChildren) return false
    var title = String(entry.text || "")
    if (!title || !root.menuTitle) return false
    return title.toLowerCase() === String(root.menuTitle).toLowerCase()
  }

  function leadingSeparatorRow(entry, index) {
    return root.depth === 0 && !!entry && entry.isSeparator === true && index <= 1
  }

  function rowVisible(entry, index) {
    if (!entry) return false
    return !rootTitleRow(entry, index) && !root.leadingSeparatorRow(entry, index)
  }

  function activateRow(entry, index) {
    if (!entry || entry.isSeparator || entry.enabled === false) return
    if (entry.hasChildren) {
      // Reset scroll BEFORE swapping the model: the swap destroys this delegate
      // synchronously and ids stop resolving after.
      if (rowsFlick) rowsFlick.contentY = 0
      root.enterSubmenu(entry, String(entry.text || ""))
      return
    }
    entry.triggered()
    root.itemTriggered()
  }

  // Keyboard cursor walks raw entry indexes and skips rows that render at zero
  // height, so Up/Down never parks on a separator.
  function moveCursor(dy) {
    var list = root.entries || []
    if (!list.length) return
    var index = root.cursor
    if (index < 0) index = dy >= 0 ? -1 : list.length
    var next = index
    for (var step = 0; step < list.length; step++) {
      next += dy >= 0 ? 1 : -1
      if (next < 0) { next = 0; break }
      if (next >= list.length) { next = list.length - 1; break }
      if (root.rowVisible(list[next], next)) break
    }
    if (root.rowVisible(list[next], next)) {
      root.cursor = next
      root.cursorMoved(next)
    }
  }

  function activateCursor() {
    var list = root.entries || []
    if (root.cursor < 0 || root.cursor >= list.length) return
    root.activateRow(list[root.cursor], root.cursor)
  }

  readonly property real headerHeight: header.visible ? header.implicitHeight : 0
  readonly property real rowsHeight: rowsColumn.implicitHeight
  readonly property real rowsViewportHeight: root.maxRowsHeight > 0
    ? Math.min(root.rowsHeight, root.maxRowsHeight)
    : root.rowsHeight

  implicitHeight: root.headerHeight + root.rowsViewportHeight

  QsMenuOpener {
    id: rootOpener
    menu: root.menuHandle
  }

  Column {
    id: layout
    width: parent.width
    spacing: 0

    // Header for a drilled-into submenu: names where we are and walks back out.
    // Pinned above the Flickable rather than scrolling with the rows, so the way
    // back stays reachable in a submenu taller than the card.
    Column {
      id: header
      visible: root.depth > 0
      width: layout.width
      spacing: 0

      Item {
        width: header.width
        implicitHeight: Style.space(30)

        Rectangle {
          anchors.fill: parent
          radius: Math.max(2, Style.cornerRadius)
          color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          text: "\u2039"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(28)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          text: root.levelTitle
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        MouseArea {
          id: backMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.settling) return
            if (rowsFlick) rowsFlick.contentY = 0
            root.leaveSubmenu()
          }
        }
      }

      Item {
        width: header.width
        implicitHeight: Style.space(11)

        Rectangle {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          height: 1
          color: Color.popups.border
          opacity: 0.45
        }
      }
    }

    Flickable {
      id: rowsFlick
      width: layout.width
      height: root.rowsViewportHeight
      contentWidth: width
      contentHeight: rowsColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      Column {
        id: rowsColumn
        width: rowsFlick.width
        spacing: 0

        Repeater {
          model: root.entries

          delegate: Item {
            id: menuRow
            required property var modelData
            required property int index

            readonly property string rowText: String(modelData.text || "")
            readonly property bool hiddenRow: !root.rowVisible(modelData, index)
            readonly property bool separator: modelData.isSeparator === true
            readonly property bool selected: root.keyboardCursor && root.cursor === index

            visible: !hiddenRow
            width: rowsColumn.width
            implicitHeight: hiddenRow ? 0 : (separator ? Style.space(11) : Style.space(30))
            opacity: modelData.enabled ? 1.0 : 0.45

            Rectangle {
              visible: menuRow.separator
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              height: 1
              color: Color.popups.border
              opacity: 0.45
            }

            Rectangle {
              visible: !menuRow.separator
              anchors.fill: parent
              radius: Math.max(2, Style.cornerRadius)
              color: (rowMouse.containsMouse || menuRow.selected) && menuRow.modelData.enabled
                ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
            }

            Text {
              textFormat: Text.PlainText
              visible: !menuRow.separator && menuRow.modelData.buttonType !== QsMenuButtonType.None
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              width: Style.space(22)
              horizontalAlignment: Text.AlignHCenter
              text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Image {
              id: menuIcon
              visible: !menuRow.separator && String(menuRow.modelData.icon || "") !== ""
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(24)
              width: Style.space(16)
              height: Style.space(16)
              fillMode: Image.PreserveAspectFit
              // Decode at physical pixels: the logical size leaves PNG icons
              // upscaled and blurry on HiDPI displays.
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: menuRow.modelData.icon
            }

            Text {
              textFormat: Text.PlainText
              visible: !menuRow.separator
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
              anchors.right: submenuGlyph.left
              anchors.rightMargin: Style.space(8)
              text: menuRow.rowText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              id: submenuGlyph
              visible: !menuRow.separator && menuRow.modelData.hasChildren
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              text: "\u203a"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: !menuRow.separator && menuRow.modelData.enabled
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onEntered: if (!menuRow.hiddenRow) root.cursor = menuRow.index
              onClicked: {
                if (root.settling) return
                root.activateRow(menuRow.modelData, menuRow.index)
              }
            }
          }
        }
      }
    }
  }

  ScrollHint {
    flickable: rowsFlick
    foreground: root.foreground
  }

}
