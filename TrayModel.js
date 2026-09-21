// SPDX-License-Identifier: MIT
//
// Pure helpers shared by the bar widget, the overflow panel, and the tests.
// This file deliberately has no QML imports so `node --test` can load it, and
// so the plugin keeps one definition of "which tray items belong here".

// QML hands us list-like values — ObjectModel.values and layout arrays read
// back through the plugin API are not always real JS Arrays. Array.isArray()
// returned false for them, which silently produced an empty list and made the
// whole widget render nothing. This copies anything with a numeric length into
// a plain JS array so callers can slice/index it freely.
function asList(value) {
  var out = []
  if (!value || typeof value.length !== "number") return out
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function layoutHasWidget(layout, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = asList(layout && layout[sections[s]])
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
}

// LocalSend's item shows no state, offers only Open and Quit, and its primary
// click is a no-op, so Share > Receive is the whole surface. Hiding it by hand
// doesn't stick either: LocalSend picks a fresh tray id every launch. The
// dedicated omarchy.dropbox widget owns Dropbox when it is on the bar.
//
// `ownsDropbox` is a plain boolean rather than the layout object: the bar hands
// the plugin a fresh layoutConfig object on every plugin sync (a click-target
// registration triggers one), so a binding that read the layout re-entered
// itself and QML reported a binding loop on trayState. A boolean only notifies
// when Dropbox ownership actually flips.
function ownedByOmarchy(item, ownsDropbox) {
  return itemNamed(item, "localsend")
    || (!!ownsDropbox && itemNamed(item, "dropbox"))
}

function trayId(item) {
  return String(item && item.id || "")
}

// Display name for a tray item: the app's own title first, then the tooltip
// title, then the tail of the (usually bus-address-shaped) id.
function trayName(item) {
  if (!item) return ""
  var title = String(item.title || "").trim()
  if (title) return title
  var tooltip = String(item.tooltipTitle || "").trim()
  if (tooltip) return tooltip
  var id = trayId(item)
  var slash = id.lastIndexOf("/")
  var name = slash !== -1 ? id.substring(slash + 1) : id
  return name || "Unknown"
}

// Symbolic icons ship a fixed fill (often near-white) that the host is meant to
// recolor to its foreground; detect them by the freedesktop "-symbolic" name
// suffix so they can be tinted instead of rendered as-is.
function isSymbolicIcon(icon) {
  var name = String(icon || "").split("?")[0]
  return name.slice(-9) === "-symbolic"
}

// Quickshell resolves the tray icon into a ready-to-use image:// URL, including
// a "?path=" fallback search dir for apps that ship their icon outside a
// standard theme. Hand it straight to Image; guessing a theme sub-directory
// here only broke apps whose layout didn't match the guess.
function iconSource(icon) {
  return String(icon || "")
}

function isHidden(hiddenIds, id) {
  return asList(hiddenIds).indexOf(String(id)) !== -1
}

// Should this item be drawn on the bar?
//
// Three ways an item ends up on the bar:
//   1. the user never hid it;
//   2. it asks for attention the standard way (StatusNotifierItem
//      Status == NeedsAttention);
//   3. it flashes by flipping its icon on a timer — WeChat does this every
//      500 ms and never touches Status — which the widget detects separately
//      and passes in as `flashing`.
//
// `attentionStatus` is Status.NeedsAttention from QML; `flashing` is a boolean
// the caller maintains (see BarWidget.noteIconChange).
function shownOnBar(item, hiddenIds, revealAttention, attentionStatus, flashing) {
  if (!item) return false
  if (!isHidden(hiddenIds, trayId(item))) return true
  if (revealAttention !== true) return false
  if (flashing === true) return true
  return attentionStatus !== undefined && item.status === attentionStatus
}

// Sliding-window bookkeeping for flash detection. Returns the next score map
// and whether the id is currently considered flashing. Kept here so the widget
// only has to wire signals to it and `node --test` can cover the thresholds.
function noteFlash(scoreMap, id, now, windowMs, minChanges) {
  var next = {}
  for (var key in scoreMap) next[key] = scoreMap[key]
  var key2 = String(id || "")
  if (!key2) return { scores: next, flashing: false }
  var entry = next[key2] || { times: [] }
  var times = []
  var list = asList(entry.times)
  for (var i = 0; i < list.length; i++) {
    if (now - list[i] < windowMs) times.push(list[i])
  }
  times.push(now)
  next[key2] = { times: times }
  return { scores: next, flashing: times.length >= minChanges }
}

// Drops ids whose last change fell outside the window, so a stopped flash
// clears itself without a second timer.
function decayFlash(scoreMap, now, windowMs) {
  var next = {}
  for (var key in scoreMap) {
    var entry = scoreMap[key]
    var list = asList(entry && entry.times)
    var kept = []
    for (var i = 0; i < list.length; i++) {
      if (now - list[i] < windowMs) kept.push(list[i])
    }
    if (kept.length > 0) next[key] = { times: kept }
  }
  return next
}

// `passiveStatus` is passed in (Status.Passive from QML) so this file stays
// free of Quickshell imports. Items with no status at all are treated as live.
function partition(items, hiddenIds, ownsDropbox, passiveStatus) {
  var shown = []
  var hidden = []
  var all = []
  var values = asList(items)
  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item) continue
    if (passiveStatus !== undefined && item.status === passiveStatus) continue
    if (ownedByOmarchy(item, ownsDropbox)) continue
    all.push(item)
    if (isHidden(hiddenIds, trayId(item))) hidden.push(item)
    else shown.push(item)
  }
  return { shown: shown, hidden: hidden, all: all }
}

// Returns a new hidden list with `id` forced to `hidden`. Unknown ids are kept
// in place: an app that is not running right now must not lose its setting.
function withHidden(hiddenIds, id, hidden) {
  var next = asList(hiddenIds)
  var key = String(id || "")
  if (!key) return next
  var index = next.indexOf(key)
  if (hidden) {
    if (index === -1) next.push(key)
  } else if (index !== -1) {
    next.splice(index, 1)
  }
  return next
}

function toggleHidden(hiddenIds, id) {
  var key = String(id || "")
  return withHidden(hiddenIds, key, !isHidden(hiddenIds, key))
}

// Union of the current hidden ids and every live item id, for "hide all".
function hiddenUnion(hiddenIds, items) {
  var next = asList(hiddenIds)
  var values = asList(items)
  for (var i = 0; i < values.length; i++) {
    var id = trayId(values[i])
    if (id && next.indexOf(id) === -1) next.push(id)
  }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    asList: asList,
    itemNamed: itemNamed,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy,
    trayId: trayId,
    trayName: trayName,
    isSymbolicIcon: isSymbolicIcon,
    iconSource: iconSource,
    isHidden: isHidden,
    shownOnBar: shownOnBar,
    noteFlash: noteFlash,
    decayFlash: decayFlash,
    partition: partition,
    withHidden: withHidden,
    toggleHidden: toggleHidden,
    hiddenUnion: hiddenUnion
  }
}
