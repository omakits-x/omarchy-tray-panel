# Tray Panel

An Omarchy bar widget that keeps system tray icons on the bar and moves the
ones you hide into a Windows-style overflow panel.

<img width="324" height="333" alt="image" src="https://github.com/user-attachments/assets/9ef05964-6517-438e-ab2e-79f954b3fb2e" />


## Features

- Tray icons live on the bar; a chevron at the end opens the overflow panel.
- Hide any icon and it moves into the panel instead of disappearing.
- Left click the chevron for the hidden icons, right click for the settings.
- Settings for every icon (show/hide), the panel position (at button / left /
  centre / right), the widget's bar section (left / centre / right) and the
  language (auto / English / 中文).
- Full tray interaction survives in both surfaces: left click activates, right
  click opens the app's own menu — rendered in place, submenus included —
  middle click secondary-activates, and the wheel is forwarded.
- Works on horizontal and vertical bars, and on every bar edge.

## Install

```bash
omarchy plugin add https://github.com/omakits-x/omarchy-tray-panel.git --enable --yes
```

No manual edits to `~/.config/omarchy/shell.json` are required.

## Update

```bash
omarchy plugin update io.github.omakitsx.tray-panel --yes
```

## Remove

```bash
omarchy plugin remove io.github.omakitsx.tray-panel --yes
```

Removing the plugin restores Omarchy's built-in system tray.

## Usage

| Action | Result |
|---|---|
| Left click the chevron | Open the overflow panel (hidden icons) |
| Right click the chevron | Open the panel on its settings view |
| Left click an icon | Activate it |
| Right click an icon on the bar | Its own menu, anchored to that icon |
| Right click an icon in the panel | Its own menu, rendered inside the panel |
| Middle click | Secondary activate |
| Wheel | Forwarded to the item |

## Settings

Settings live inline in the widget's `shell.json` entry:

```json
{
  "id": "io.github.omakitsx.tray-panel",
  "hidden": ["app_status_icon_1"],
  "panelPlacement": "button",
  "language": "auto"
}
```

- `hidden` — tray item ids that move into the overflow panel. Every other icon
  stays on the bar. Unknown ids are kept, so an app that is not running keeps
  its setting.
- `panelPlacement` — `button` (under the chevron), `left`, `center`, `right`.
- `language` — `auto` (follow the locale), `en`, `zh`.

The bar section is not stored here: choosing one in the settings runs
`omarchy bar move io.github.omakitsx.tray-panel --section <section>`, so the
widget moves exactly as it would from the CLI.

## Development

```bash
omarchy plugin validate .
npm test
qmllint -I "$OMARCHY_PATH/shell" *.qml
```

## Notes for plugin authors

Two platform behaviours cost the most time while building this plugin; both are
recorded in the `omarchy-plugin` skill with reproduction and fix:

- `QtQuick.Controls` types such as `ScrollBar` do not resolve inside a
  third-party plugin — the type lives in the Controls style module, which the
  shell does not load for user plugins, so the whole component fails with
  `ScrollBar is not a type`. Draw the affordance yourself (see `ScrollHint.qml`)
  or use `qs.Ui` components. The built-in widgets can use them because they are
  compiled inside the shell itself.
- `SystemTray.items.values` is list-like, not a real JS `Array`, so
  `Array.isArray()` returns false and any partition built on it silently
  produces nothing — the widget then renders as `visible: false` with no error.

## Credits

The tray icon rendering, menu drill-down and menu-row markup derive from
Omarchy's MIT-licensed `Tray.qml`; the plugin keeps that licence.

## License

MIT. See [LICENSE](LICENSE).
