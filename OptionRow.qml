// SPDX-License-Identifier: MIT
//
// One settings row: a caption on the left, a mutually-exclusive set of toggle
// chips on the right.
//
// The chips are qs.Ui's ButtonGroup — the shell's own "pick one of N" control.
// Using it instead of another hand-rolled Repeater means the panel's option
// rows share one implementation: the chips paint selected / hover / cursor
// from the same Style tokens as every other control, and h/l + Enter work on
// them for free. This file only adds what the panel needs on top of that.
//
// The caption column is that addition. `labelWidth` is set by the owner to the
// widest caption in the current language (Panel.qml measures it), which is what
// keeps "Panel position" from running under the chips in English while Chinese
// keeps the compact column it has always had. With the default 0 the caption
// takes its natural width — the per-icon Show/Hide rows want no caption at all.
//
// `value` is a string because ButtonGroup keys its options by string; a
// boolean setting stays the caller's business ("on"/"off" in Panel.qml).

import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: root

  property string label: ""
  property var options: []
  property string value: ""
  // 0 = the caption takes its natural width instead of a shared column.
  property real labelWidth: 0
  property real fontSize: Style.font.caption
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal selected(string value)

  spacing: Style.space(6)

  Text {
    id: caption
    visible: root.label !== ""
    anchors.verticalCenter: parent.verticalCenter
    width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    elide: Text.ElideRight
  }

  ButtonGroup {
    id: chips
    anchors.verticalCenter: parent.verticalCenter
    options: root.options
    value: root.value
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: root.fontSize
    // ButtonGroup defaults this to Color.background, which is the *bar*
    // background. The panel card is a popup: filling its chips with the bar
    // color would paint opaque rectangles over a translucent card, so the
    // chips stay transparent at rest and rely on Button's border + selected
    // fill like every other control in this plugin.
    background: "transparent"
    // The panel owns the keyboard cursor for its icon list and menu; a Tab
    // stop per chip group would compete with it.
    focusable: false
    onChanged: function(value) { root.selected(value) }
  }
}
