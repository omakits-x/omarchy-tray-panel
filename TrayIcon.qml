// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Effects
import qs.Commons
import "TrayModel.js" as TrayModel

// Renders one system tray icon, recoloring symbolic icons to the host
// foreground so they stay visible on any theme (a raw symbolic icon keeps its
// baked-in fill and disappears against a matching background).
Item {
  id: root

  required property var icon
  property color color: Color.foreground

  readonly property bool symbolic: TrayModel.isSymbolicIcon(root.icon)

  Image {
    id: image
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    // Decode at physical pixels: the logical size alone leaves PNG icons
    // upscaled and blurry on HiDPI displays.
    sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    source: TrayModel.iconSource(root.icon)
    // Kept as a hidden layer so the effect can sample it as a texture.
    visible: !root.symbolic
    layer.enabled: root.symbolic
  }

  MultiEffect {
    anchors.fill: image
    source: image
    visible: root.symbolic
    colorization: 1.0
    colorizationColor: root.color
  }
}
