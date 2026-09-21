// SPDX-License-Identifier: MIT

import QtQuick
import qs.Commons

// A slim scroll indicator for a Flickable, drawn from theme tokens.
//
// QtQuick.Controls' ScrollBar is not usable from a third-party shell plugin:
// its type is defined in the Controls style module (QtQuick.Controls.Basic),
// which does not resolve in the context the shell compiles user plugins in.
// The built-in widgets can use it — they are compiled inside the shell itself —
// but a user plugin gets "ScrollBar is not a type" and the whole component
// fails to load. This draws the same affordance without that dependency, in the
// bar's own palette.
//
// Place it as a sibling of `flickable` (same parent), or anywhere whose origin
// matches the flickable's origin.
Rectangle {
  id: root

  required property Flickable flickable
  property color foreground: Color.foreground
  property real thickness: Math.max(2, Math.round(Style.space(3)))
  property real minLength: Math.round(Style.space(18))
  property real inset: Math.round(Style.space(2))

  readonly property bool needed: !!flickable && flickable.contentHeight > flickable.height + 1
  readonly property real trackLength: flickable ? flickable.height : 0
  readonly property real maxOffset: flickable ? Math.max(1, flickable.contentHeight - flickable.height) : 1
  readonly property real offsetRatio: flickable
    ? Math.min(1, Math.max(0, flickable.contentY / maxOffset)) : 0

  visible: needed
  width: thickness
  height: needed
    ? Math.max(minLength, trackLength * (flickable.height / Math.max(1, flickable.contentHeight)))
    : 0
  radius: width / 2
  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
  x: flickable ? flickable.x + flickable.width - width - inset : 0
  y: flickable ? flickable.y + Math.round((trackLength - height) * offsetRatio) : 0
}
