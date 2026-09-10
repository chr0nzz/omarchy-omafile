'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var loadModule = require('./load.js');

var Icons = loadModule('Icons.js');
var Model = loadModule('Model.js');

var MDI_MIN = 0xF0001;
var MDI_MAX = 0xF1AF0;
var FA_MIN = 0xF000;
var FA_MAX = 0xF2E0;
var OCT_MIN = 0xF400;
var OCT_MAX = 0xF532;

function inAllowedRange(codePoint) {
  return (codePoint >= MDI_MIN && codePoint <= MDI_MAX) ||
    (codePoint >= FA_MIN && codePoint <= FA_MAX) ||
    (codePoint >= OCT_MIN && codePoint <= OCT_MAX);
}

function assertValidGlyph(glyph, label) {
  assert.equal(typeof glyph, 'string', label + ' should be a string');
  assert.ok(glyph.length > 0, label + ' should not be empty');
  var codePoints = Array.from(glyph);
  assert.equal(codePoints.length, 1, label + ' should be exactly one code point, got ' + JSON.stringify(glyph));
  var cp = glyph.codePointAt(0);
  assert.ok(inAllowedRange(cp), label + ' code point U+' + cp.toString(16).toUpperCase() + ' is outside the allowed ranges');
}

var placeKeys = ['home', 'desktop', 'documents', 'downloads', 'music', 'pictures', 'videos',
  'templates', 'publicshare', 'trash', 'root', 'drive', 'usb', 'network', 'pinned', 'recent', 'search'];

var actionKeys = ['copy', 'cut', 'paste', 'rename', 'trash', 'delete', 'newfolder', 'newfile', 'up',
  'back', 'forward', 'refresh', 'search', 'hidden', 'list', 'grid', 'columns', 'split', 'close', 'add',
  'sort', 'menu', 'eject', 'open', 'terminal', 'editor', 'properties', 'cancel', 'check', 'warning',
  'error', 'chevronRight', 'chevronDown', 'chevronUp', 'chevronLeft'];

var categoryKeys = ['folder', 'image', 'video', 'audio', 'archive', 'code', 'document', 'pdf', 'font',
  'executable', 'link', 'broken', 'file'];

test('placeGlyph returns a valid single code point glyph for every known key', function () {
  placeKeys.forEach(function (key) {
    assertValidGlyph(Icons.placeGlyph(key), 'placeGlyph(' + key + ')');
  });
});

test('placeGlyph falls back to a generic glyph for an unknown key', function () {
  assertValidGlyph(Icons.placeGlyph('nonexistent-key'), 'placeGlyph(unknown)');
  assertValidGlyph(Icons.placeGlyph(''), 'placeGlyph(empty)');
  assertValidGlyph(Icons.placeGlyph(undefined), 'placeGlyph(undefined)');
});

test('actionGlyph returns a valid single code point glyph for every known name', function () {
  actionKeys.forEach(function (name) {
    assertValidGlyph(Icons.actionGlyph(name), 'actionGlyph(' + name + ')');
  });
});

test('actionGlyph distinguishes chevron directions', function () {
  var up = Icons.actionGlyph('chevronUp');
  var down = Icons.actionGlyph('chevronDown');
  var left = Icons.actionGlyph('chevronLeft');
  var right = Icons.actionGlyph('chevronRight');
  assert.notEqual(up, down);
  assert.notEqual(left, right);
  assert.notEqual(up, left);
});

test('actionGlyph falls back to a generic glyph for an unknown name', function () {
  assertValidGlyph(Icons.actionGlyph('doesnotexist'), 'actionGlyph(unknown)');
});

test('glyphForCategory returns a valid single code point glyph for every category', function () {
  categoryKeys.forEach(function (category) {
    assertValidGlyph(Icons.glyphForCategory(category), 'glyphForCategory(' + category + ')');
  });
});

test('glyphForCategory falls back to a generic glyph for an unknown category', function () {
  assertValidGlyph(Icons.glyphForCategory('not-a-category'), 'glyphForCategory(unknown)');
});

test('glyphFor dispatches on category for directories, links and broken links', function () {
  var dir = Model.decodeEntry(['dir', 'd', 0, 0, 16877, null], '/x');
  var symDir = Model.decodeEntry(['sd', 'L', 0, 0, 41453, '/t'], '/x');
  var symFile = Model.decodeEntry(['sf', 'l', 0, 0, 41471, '/t'], '/x');
  var broken = Model.decodeEntry(['bl', 'b', 0, 0, 41471, '/missing'], '/x');
  var exec = Model.decodeEntry(['run.sh', 'f', 1, 0, 33261, null], '/x');

  assertValidGlyph(Icons.glyphFor(dir), 'glyphFor(dir)');
  assertValidGlyph(Icons.glyphFor(symDir), 'glyphFor(symDir)');
  assertValidGlyph(Icons.glyphFor(symFile), 'glyphFor(symFile)');
  assertValidGlyph(Icons.glyphFor(broken), 'glyphFor(broken)');
  assertValidGlyph(Icons.glyphFor(exec), 'glyphFor(exec)');

  assert.equal(Icons.glyphFor(dir), Icons.glyphForCategory('folder'));
  assert.equal(Icons.glyphFor(broken), Icons.glyphForCategory('broken'));
  assert.equal(Icons.glyphFor(exec), Icons.glyphForCategory('executable'));
});

test('glyphFor dispatches on extension within a category', function () {
  var exts = ['png', 'jpg', 'gif', 'mp4', 'mp3', 'zip', 'js', 'py', 'txt', 'md', 'pdf', 'ttf', 'html', 'css', 'docx', 'xlsx', 'pptx', 'unknownext'];
  exts.forEach(function (ext) {
    var entry = Model.decodeEntry(['file.' + ext, 'f', 1, 0, 33188, null], '/x');
    assertValidGlyph(Icons.glyphFor(entry), 'glyphFor(.' + ext + ')');
  });
});

test('glyphFor never calls into Model.js', function () {
  var source = require('node:fs').readFileSync(require('node:path').join(__dirname, '..', 'Icons.js'), 'utf8');
  assert.equal(/Model\./.test(source), false);
});

test('glyphFor falls back to a non empty glyph for a null entry', function () {
  assertValidGlyph(Icons.glyphFor(null), 'glyphFor(null)');
});

test('every glyph across all lookup tables is a single valid code point', function () {
  var all = [];
  placeKeys.forEach(function (k) { all.push(Icons.placeGlyph(k)); });
  actionKeys.forEach(function (k) { all.push(Icons.actionGlyph(k)); });
  categoryKeys.forEach(function (k) { all.push(Icons.glyphForCategory(k)); });
  all.forEach(function (glyph) {
    assertValidGlyph(glyph, 'glyph ' + glyph);
  });
});
