const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

const TrayModel = require("../TrayModel.js");
const I18n = require("../I18n.js");

// ------------------------------------------------------------------ manifest

test("manifest declares a namespaced bar widget with no clone metadata", () => {
  const manifest = JSON.parse(read("manifest.json"));
  const packageMetadata = JSON.parse(read("package.json"));

  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.id, "io.github.omakitsx.tray-panel");
  assert.equal(manifest.version, packageMetadata.version);
  assert.equal(manifest.license, "MIT");
  assert.deepEqual(manifest.kinds, ["bar-widget"]);
  assert.equal(manifest.entryPoints.barWidget, "BarWidget.qml");
  assert.equal(manifest.barWidget.defaultSection, "right");
  assert.equal(manifest.barWidget.allowMultiple, false);
  // A published plugin must not claim the built-in tray's identity.
  assert.equal("omarchy" in manifest, false);
  assert.equal(fs.existsSync(path.join(root, "BarWidget.qml")), true);
  assert.equal(fs.existsSync(path.join(root, "Panel.qml")), true);
  assert.equal(fs.existsSync(path.join(root, "TrayModel.js")), true);
  assert.equal(fs.existsSync(path.join(root, "I18n.js")), true);
});

test("plugin folder contains no symlinks", () => {
  const entries = fs.readdirSync(root, { withFileTypes: true, recursive: true });
  for (const entry of entries) {
    assert.equal(entry.isSymbolicLink(), false, `${entry.name} must not be a symlink`);
  }
});

// ----------------------------------------------------------------- TrayModel

const item = (id, extra) => Object.assign({ id, title: "", tooltipTitle: "", status: 1 }, extra);

test("trayName prefers title, then tooltip, then the id tail", () => {
  assert.equal(TrayModel.trayName(item(":1.5", { title: "Steam" })), "Steam");
  assert.equal(TrayModel.trayName(item(":1.5", { tooltipTitle: "Steam" })), "Steam");
  assert.equal(TrayModel.trayName(item("/org/ayatana/NotificationItem/dropbox")), "dropbox");
  assert.equal(TrayModel.trayName(null), "");
});

test("isSymbolicIcon only matches the freedesktop -symbolic suffix", () => {
  assert.equal(TrayModel.isSymbolicIcon("audio-volume-muted-symbolic"), true);
  assert.equal(TrayModel.isSymbolicIcon("image://icon/audio-volume-muted-symbolic?path=/tmp"), true);
  assert.equal(TrayModel.isSymbolicIcon("steam_tray_mono"), false);
  assert.equal(TrayModel.isSymbolicIcon(""), false);
});

test("partition splits shown and hidden and drops passive items", () => {
  const values = [
    item("a"),
    item("b"),
    item("c", { status: 0 }) // Status.Passive
  ];
  const result = TrayModel.partition(values, ["b"], null, 0);

  assert.deepEqual(result.all.map(entry => entry.id), ["a", "b"]);
  assert.deepEqual(result.shown.map(entry => entry.id), ["a"]);
  assert.deepEqual(result.hidden.map(entry => entry.id), ["b"]);
});

test("partition keeps every icon on the bar when nothing is hidden", () => {
  const values = [item("a"), item("b")];
  const result = TrayModel.partition(values, [], false, 0);

  assert.deepEqual(result.shown.map(entry => entry.id), ["a", "b"]);
  assert.deepEqual(result.hidden, []);
});

test("partition ignores the items omarchy already owns", () => {
  const values = [
    item(":1.9", { title: "LocalSend" }),
    item(":1.10", { title: "Dropbox" }),
    item(":1.11", { title: "Keep" })
  ];
  // LocalSend is always dropped: its tray item is useless and its id changes
  // every launch, so it can never be hidden by id.
  const withoutDropboxWidget = TrayModel.partition(values, [], false, 0);
  assert.deepEqual(withoutDropboxWidget.all.map(entry => entry.title), ["Dropbox", "Keep"]);

  // Dropbox only steps aside while the dedicated widget is on the bar.
  const withDropboxWidget = TrayModel.partition(values, [], true, 0);
  assert.deepEqual(withDropboxWidget.all.map(entry => entry.title), ["Keep"]);
});

test("layoutHasWidget reads both string and object entries", () => {
  const layout = { left: [{ id: "omarchy.menu" }], right: ["omarchy.dropbox"] };
  assert.equal(TrayModel.layoutHasWidget(layout, "omarchy.menu"), true);
  assert.equal(TrayModel.layoutHasWidget(layout, "omarchy.dropbox"), true);
  assert.equal(TrayModel.layoutHasWidget(layout, "omarchy.tray"), false);
});

test("withHidden keeps unknown ids so stopped apps keep their setting", () => {
  assert.deepEqual(TrayModel.withHidden(["gone"], "a", true), ["gone", "a"]);
  assert.deepEqual(TrayModel.withHidden(["a", "b"], "a", false), ["b"]);
  // No duplicates when the id is already hidden.
  assert.deepEqual(TrayModel.withHidden(["a"], "a", true), ["a"]);
  assert.deepEqual(TrayModel.withHidden(null, "a", true), ["a"]);
  assert.deepEqual(TrayModel.withHidden(["a"], "", true), ["a"]);
});

test("toggleHidden flips one id at a time", () => {
  assert.deepEqual(TrayModel.toggleHidden([], "a"), ["a"]);
  assert.deepEqual(TrayModel.toggleHidden(["a"], "a"), []);
});

test("hiddenUnion adds every live id for hide-all", () => {
  const values = [item("a"), item("b")];
  assert.deepEqual(TrayModel.hiddenUnion(["gone"], values), ["gone", "a", "b"]);
});

test("shownOnBar keeps hidden icons off the bar, and reveals them on attention", () => {
  const plain = item("a");
  const attention = item("a", { status: 2 }); // NeedsAttention

  assert.equal(TrayModel.shownOnBar(plain, [], true, 2, false), true);
  assert.equal(TrayModel.shownOnBar(plain, ["a"], true, 2, false), false);
  assert.equal(TrayModel.shownOnBar(attention, ["a"], true, 2, false), true);
  // setting off: nothing is revealed
  assert.equal(TrayModel.shownOnBar(attention, ["a"], false, 2, false), false);
});

test("shownOnBar reveals a hidden icon that flashes its own icon", () => {
  // WeChat keeps Status == Active and flips the pixmap every 500 ms instead.
  const flashing = item("wechat", { status: 1 });
  assert.equal(TrayModel.shownOnBar(flashing, ["wechat"], true, 2, true), true);
  assert.equal(TrayModel.shownOnBar(flashing, ["wechat"], true, 2, false), false);
});

test("noteFlash only flags a sustained burst inside the window", () => {
  let scores = {};
  let r = TrayModel.noteFlash(scores, "wechat", 1000, 1200, 2);
  scores = r.scores;
  assert.equal(r.flashing, false, "a single icon change is not a flash");
  r = TrayModel.noteFlash(scores, "wechat", 1500, 1200, 2);
  scores = r.scores;
  assert.equal(r.flashing, true, "second change inside the window is a flash");
  // a change far outside the window does not accumulate
  r = TrayModel.noteFlash(scores, "wechat", 9000, 1200, 2);
  assert.equal(r.flashing, false);
});

test("decayFlash clears a flash that stopped", () => {
  let scores = TrayModel.noteFlash({}, "wechat", 1000, 1200, 2).scores;
  scores = TrayModel.noteFlash(scores, "wechat", 1500, 1200, 2).scores;
  assert.deepEqual(TrayModel.decayFlash(scores, 5000, 1200), {});
});

// ---------------------------------------------------------------------- I18n

test("detectLanguage maps zh locales to Chinese and everything else to English", () => {
  assert.equal(I18n.detectLanguage("zh_CN"), "zh");
  assert.equal(I18n.detectLanguage("zh-Hans-CN"), "zh");
  assert.equal(I18n.detectLanguage("ZH"), "zh");
  assert.equal(I18n.detectLanguage("en_US"), "en");
  assert.equal(I18n.detectLanguage("de_DE"), "en");
  assert.equal(I18n.detectLanguage(""), "en");
});

test("resolveLanguage honors an explicit choice and falls back to the locale", () => {
  assert.equal(I18n.resolveLanguage("zh", "en_US"), "zh");
  assert.equal(I18n.resolveLanguage("en", "zh_CN"), "en");
  assert.equal(I18n.resolveLanguage("auto", "zh_CN"), "zh");
  assert.equal(I18n.resolveLanguage("auto", "en_US"), "en");
  assert.equal(I18n.resolveLanguage("nonsense", "zh_CN"), "zh");
  assert.equal(I18n.resolveLanguage(undefined, "en_US"), "en");
});

test("both language tables cover exactly the same keys", () => {
  const english = Object.keys(I18n.strings.en).sort();
  const chinese = Object.keys(I18n.strings.zh).sort();
  assert.deepEqual(chinese, english);
  for (const key of english) {
    assert.notEqual(I18n.strings.en[key].trim(), "", `${key} needs an English string`);
    assert.notEqual(I18n.strings.zh[key].trim(), "", `${key} needs a Chinese string`);
  }
});

test("text falls back to English and then to the key itself", () => {
  assert.equal(I18n.text("zh", "panel.action.hide"), "隐藏");
  assert.equal(I18n.text("en", "panel.action.hide"), "Hide");
  assert.equal(I18n.text("de", "panel.action.hide"), "Hide");
  assert.equal(I18n.text("en", "missing.key"), "missing.key");
});

// ------------------------------------------------------------- source checks

test("the bar keeps every icon visible unless the user hides it", () => {
  const source = read("BarWidget.qml");
  // Default classification is "on the bar"; only the hidden list moves icons
  // into the panel.
  assert.match(source, /readonly property var hiddenIds: settings\.hidden instanceof Array \? settings\.hidden : \[\]/);
  // Visibility is decided per delegate by a binding (so a status flip or a
  // detected flash re-evaluates it), not by a JS partition that would
  // never re-run when an item's own properties change.
  assert.match(source, /model: root\.allItems/);
  assert.match(source, /visible: root\.itemShownOnBar\(modelData\)/);
});

test("settings persist through the inline shell.json entry", () => {
  const source = read("BarWidget.qml");
  assert.match(source, /bar\.shell\.updateEntryInline\(root\.moduleName, entry\)/);
  // Merging matters: updateEntryInline replaces the whole entry.
  assert.match(source, /for \(var key in root\.settings\) if \(key !== "id"\) entry\[key\] = root\.settings\[key\]/);
});

test("panel and bar menu share one renderer and one popout owner", () => {
  const bar = read("BarWidget.qml");
  const panel = read("Panel.qml");
  assert.match(bar, /TrayMenuList \{/);
  assert.match(panel, /TrayMenuList \{/);
  assert.match(bar, /owner: root/);
  assert.match(panel, /owner: root\.barIdentity/);
});
