// SPDX-License-Identifier: MIT
//
// Bilingual (English / Chinese) string table for the tray panel plugin.
//
// A shell plugin is installed from a plain git checkout, so there is no
// lrelease/lupdate step to hook into and Qt's .qm machinery is not available.
// A small lookup table keyed by string id keeps the UI translatable without
// any build tooling, and `node --test` can exercise it directly.
//
// No `.pragma library` here on purpose: the file is shared with the Node test
// runner, which cannot parse QML pragmas.

var LANGUAGES = ["en", "zh"]

var strings = {
  en: {
    "bar.hidden": "Hidden icons",
    "bar.settings": "Tray settings",

    "panel.hidden.title": "Hidden icons",
    "panel.settings.title": "Tray icons",
    "panel.menu.title": "Menu",

    "panel.hidden.empty": "No hidden icons. Every tray icon is on the bar.",
    "panel.tray.empty": "No tray icons are reporting.",

    "panel.settings.hint": "Choose which icons stay on the bar. Hidden icons move into this panel.",

    "panel.action.hide": "Hide",
    "panel.action.show": "Show",
    "panel.action.hideAll": "Hide all",
    "panel.action.showAll": "Show all",
    "panel.action.settings": "Settings",
    "panel.action.back": "Back",

    "panel.language": "Language",
    "panel.language.auto": "Auto",
    "panel.placement": "Panel position",
    "panel.placement.button": "At button",
    "panel.placement.left": "Left",
    "panel.placement.center": "Center",
    "panel.placement.right": "Right",
    "panel.barPosition": "Tray position",

    "status.shown": "Shown",
    "status.hidden": "Hidden"
  },
  zh: {
    "bar.hidden": "隐藏的图标",
    "bar.settings": "托盘设置",

    "panel.hidden.title": "隐藏的图标",
    "panel.settings.title": "托盘图标",
    "panel.menu.title": "菜单",

    "panel.hidden.empty": "没有隐藏的图标，所有托盘图标都显示在栏上。",
    "panel.tray.empty": "当前没有托盘图标。",

    "panel.settings.hint": "选择哪些图标留在栏上。隐藏的图标会收进这个面板。",

    "panel.action.hide": "隐藏",
    "panel.action.show": "显示",
    "panel.action.hideAll": "全部隐藏",
    "panel.action.showAll": "全部显示",
    "panel.action.settings": "设置",
    "panel.action.back": "返回",

    "panel.language": "语言",
    "panel.language.auto": "自动",
    "panel.placement": "面板位置",
    "panel.placement.button": "跟随按钮",
    "panel.placement.left": "左",
    "panel.placement.center": "中",
    "panel.placement.right": "右",
    "panel.barPosition": "托盘位置",

    "status.shown": "显示中",
    "status.hidden": "已隐藏"
  }
}

// "zh_CN", "zh-Hans-CN", "ZH" -> "zh"; anything else -> "en".
function detectLanguage(localeName) {
  var name = String(localeName || "").toLowerCase()
  return name.indexOf("zh") === 0 ? "zh" : "en"
}

// `preference` is the stored setting ("auto", "en" or "zh"). Anything unknown
// falls back to the locale, so a hand-edited shell.json cannot leave the plugin
// with no language at all.
function resolveLanguage(preference, localeName) {
  var value = String(preference === undefined || preference === null ? "auto" : preference).toLowerCase()
  if (LANGUAGES.indexOf(value) !== -1) return value
  return detectLanguage(localeName)
}

function text(language, key) {
  var table = strings[language] || strings.en
  var value = table[key]
  if (value === undefined) value = strings.en[key]
  return value === undefined ? String(key) : value
}

if (typeof module !== "undefined") {
  module.exports = {
    LANGUAGES: LANGUAGES,
    strings: strings,
    detectLanguage: detectLanguage,
    resolveLanguage: resolveLanguage,
    text: text
  }
}
