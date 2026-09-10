'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var loadModule = require('./load.js');

var Model = loadModule('Model.js');

function arrayLike(items) {
  var obj = {};
  for (var i = 0; i < items.length; i++) obj[i] = items[i];
  obj.length = items.length;
  return obj;
}

function pluck(list, key) {
  var out = [];
  for (var i = 0; i < list.length; i++) out.push(list[i][key]);
  return out;
}

function plainCrumbs(list) {
  var out = [];
  for (var i = 0; i < list.length; i++) out.push({ label: list[i].label, path: list[i].path });
  return out;
}

test('natural sort orders file2 before file10', function () {
  var entries = Model.decodeEntries([
    ['file10', 'f', 1, 0, 33188, null],
    ['file2', 'f', 1, 0, 33188, null],
    ['file1', 'f', 1, 0, 33188, null]
  ], '/d');
  var sorted = Model.sortEntries(entries, 'name', false, false);
  assert.deepEqual(pluck(sorted, 'name'), ['file1', 'file2', 'file10']);
});

test('natural sort is case insensitive', function () {
  var entries = Model.decodeEntries([
    ['Banana', 'f', 1, 0, 33188, null],
    ['apple', 'f', 1, 0, 33188, null],
    ['Cherry', 'f', 1, 0, 33188, null]
  ], '/d');
  var sorted = Model.sortEntries(entries, 'name', false, false);
  assert.deepEqual(pluck(sorted, 'name'), ['apple', 'Banana', 'Cherry']);
});

test('sortEntries does not mutate input array', function () {
  var entries = Model.decodeEntries([
    ['b', 'f', 1, 0, 33188, null],
    ['a', 'f', 1, 0, 33188, null]
  ], '/d');
  var original = entries.slice();
  Model.sortEntries(entries, 'name', false, false);
  assert.deepEqual(entries, original);
});

test('dirsFirst groups symlinked directories with real directories', function () {
  var entries = Model.decodeEntries([
    ['zfile', 'f', 1, 0, 33188, null],
    ['alink', 'L', 0, 0, 41453, '/target'],
    ['bdir', 'd', 0, 0, 16877, null],
    ['afile', 'f', 1, 0, 33188, null]
  ], '/d');
  var sorted = Model.sortEntries(entries, 'name', false, true);
  assert.deepEqual(pluck(sorted, 'name'), ['alink', 'bdir', 'afile', 'zfile']);
  assert.equal(sorted[0].isDir, true);
  assert.equal(sorted[1].isDir, true);
});

test('dirsFirst grouping holds when descending', function () {
  var entries = Model.decodeEntries([
    ['zfile', 'f', 1, 0, 33188, null],
    ['alink', 'L', 0, 0, 41453, '/target'],
    ['bdir', 'd', 0, 0, 16877, null]
  ], '/d');
  var sorted = Model.sortEntries(entries, 'name', true, true);
  assert.equal(sorted[0].isDir, true);
  assert.equal(sorted[1].isDir, true);
  assert.equal(sorted[2].name, 'zfile');
});

test('filterEntries returns all entries for an empty query', function () {
  var entries = Model.decodeEntries([
    ['a', 'f', 1, 0, 33188, null],
    ['b', 'f', 1, 0, 33188, null]
  ], '/d');
  var filtered = Model.filterEntries(entries, '', true);
  assert.equal(filtered.length, 2);
});

test('filterEntries matches case insensitive substrings', function () {
  var entries = Model.decodeEntries([
    ['Report.txt', 'f', 1, 0, 33188, null],
    ['notes.md', 'f', 1, 0, 33188, null]
  ], '/d');
  var filtered = Model.filterEntries(entries, 'rep', true);
  assert.deepEqual(pluck(filtered, 'name'), ['Report.txt']);
});

test('filterEntries excludes hidden entries when showHidden is false', function () {
  var entries = Model.decodeEntries([
    ['.hidden', 'f', 1, 0, 33188, null],
    ['visible', 'f', 1, 0, 33188, null]
  ], '/d');
  var filtered = Model.filterEntries(entries, '', false);
  assert.deepEqual(pluck(filtered, 'name'), ['visible']);
});

test('formatSize branches', function () {
  assert.equal(Model.formatSize(0), '0 B');
  assert.equal(Model.formatSize(221), '221 B');
  assert.equal(Model.formatSize(1023), '1023 B');
  assert.equal(Model.formatSize(1229), '1.2 KB');
  assert.equal(Model.formatSize(4 * 1024 * 1024), '4.0 MB');
  assert.equal(Model.formatSize(Math.round(1.1 * 1024 * 1024 * 1024)), '1.1 GB');
  assert.equal(Model.formatSize(Math.round(2.3 * 1024 * 1024 * 1024 * 1024)), '2.3 TB');
  assert.equal(Model.formatSize(-5), '0 B');
});

test('formatEta branches', function () {
  assert.equal(Model.formatEta(12), '12s');
  assert.equal(Model.formatEta(252), '4m 12s');
  assert.equal(Model.formatEta(3840), '1h 04m');
  assert.equal(Model.formatEta(-1), '--');
  assert.equal(Model.formatEta(Infinity), '--');
  assert.equal(Model.formatEta(NaN), '--');
});

test('formatDate branches', function () {
  var now = new Date(2026, 2, 4, 14, 3, 22).getTime();
  var todaySeconds = Math.floor(new Date(2026, 2, 4, 14, 3, 0).getTime() / 1000);
  var yesterdaySeconds = Math.floor(new Date(2026, 2, 3, 9, 0, 0).getTime() / 1000);
  var sameYearSeconds = Math.floor(new Date(2026, 0, 15, 9, 0, 0).getTime() / 1000);
  var otherYearSeconds = Math.floor(new Date(2024, 2, 4, 9, 0, 0).getTime() / 1000);

  assert.equal(Model.formatDate(todaySeconds, now), '14:03');
  assert.equal(Model.formatDate(yesterdaySeconds, now), 'Yesterday');
  assert.equal(Model.formatDate(sameYearSeconds, now), 'Jan 15');
  assert.equal(Model.formatDate(otherYearSeconds, now), '2024-03-04');
});

test('formatFullDate formats with zero padded components', function () {
  var seconds = Math.floor(new Date(2026, 2, 4, 14, 3, 22).getTime() / 1000);
  assert.equal(Model.formatFullDate(seconds), '2026-03-04 14:03:22');
});

test('formatMode against real st_mode integers', function () {
  assert.equal(Model.formatMode(0o40755), 'drwxr-xr-x');
  assert.equal(Model.formatMode(0o100644), '-rw-r--r--');
  assert.equal(Model.formatMode(0o120777), 'lrwxrwxrwx');
});

test('formatRate appends a per second suffix', function () {
  assert.equal(Model.formatRate(0), '0 B/s');
  assert.equal(Model.formatRate(4 * 1024 * 1024), '4.0 MB/s');
});

test('formatCount picks singular or plural', function () {
  assert.equal(Model.formatCount(1, 'item', 'items'), '1 item');
  assert.equal(Model.formatCount(2, 'item', 'items'), '2 items');
  assert.equal(Model.formatCount(0, 'item', 'items'), '0 items');
});

test('normalizePath collapses slashes, dots and dot-dot sequences', function () {
  assert.equal(Model.normalizePath('/a//b/./c/../d/'), '/a/b/d');
  assert.equal(Model.normalizePath('/'), '/');
  assert.equal(Model.normalizePath('/a/'), '/a');
  assert.equal(Model.normalizePath('/../../a'), '/a');
  assert.equal(Model.normalizePath(''), '/');
});

test('basename dirname joinPath parentPath', function () {
  assert.equal(Model.basename('/a/b/c.txt'), 'c.txt');
  assert.equal(Model.basename('/a/b/'), 'b');
  assert.equal(Model.dirname('/a/b/c.txt'), '/a/b');
  assert.equal(Model.joinPath('/a/b', 'c.txt'), '/a/b/c.txt');
  assert.equal(Model.joinPath('/', 'c.txt'), '/c.txt');
  assert.equal(Model.parentPath('/a/b'), '/a');
  assert.equal(Model.parentPath('/a'), '/');
  assert.equal(Model.parentPath('/'), '/');
});

test('expandTilde and collapseTilde', function () {
  assert.equal(Model.expandTilde('~', '/home/u'), '/home/u');
  assert.equal(Model.expandTilde('~/docs', '/home/u'), '/home/u/docs');
  assert.equal(Model.expandTilde('/etc', '/home/u'), '/etc');
  assert.equal(Model.collapseTilde('/home/u/docs', '/home/u'), '~/docs');
  assert.equal(Model.collapseTilde('/home/u', '/home/u'), '~');
  assert.equal(Model.collapseTilde('/etc', '/home/u'), '/etc');
});

test('breadcrumbs for root path', function () {
  var crumbs = Model.breadcrumbs('/');
  assert.deepEqual(plainCrumbs(crumbs), [{ label: '/', path: '/' }]);
});

test('breadcrumbs for a nested path', function () {
  var crumbs = Model.breadcrumbs('/home/user/docs');
  assert.deepEqual(plainCrumbs(crumbs), [
    { label: '/', path: '/' },
    { label: 'home', path: '/home' },
    { label: 'user', path: '/home/user' },
    { label: 'docs', path: '/home/user/docs' }
  ]);
});

test('isAncestor', function () {
  assert.equal(Model.isAncestor('/', '/a'), true);
  assert.equal(Model.isAncestor('/', '/'), false);
  assert.equal(Model.isAncestor('/a', '/a/b'), true);
  assert.equal(Model.isAncestor('/a', '/ab'), false);
  assert.equal(Model.isAncestor('/a/b', '/a'), false);
});

test('completePath returns the longest common prefix', function () {
  var names = ['report-jan.txt', 'report-feb.txt', 'readme.md'];
  assert.equal(Model.completePath('rep', names), 'report-');
  assert.equal(Model.completePath('report-j', names), 'report-jan.txt');
  assert.equal(Model.completePath('zzz', names), 'zzz');
});

test('uniqueName preserves extensions and resolves repeat collisions', function () {
  assert.equal(Model.uniqueName('a.txt', []), 'a.txt');
  assert.equal(Model.uniqueName('a.txt', ['a.txt']), 'a (copy).txt');
  assert.equal(Model.uniqueName('a.txt', ['a.txt', 'a (copy).txt']), 'a (copy 2).txt');
  assert.equal(Model.uniqueName('a.txt', ['a.txt', 'a (copy).txt', 'a (copy 2).txt']), 'a (copy 3).txt');
  assert.equal(Model.uniqueName('noext', ['noext']), 'noext (copy)');
  assert.equal(Model.pasteTargetName('a.txt', ['a.txt']), 'a (copy).txt');
});

test('decodeEntries handles an array-like chunk where Array.isArray is false', function () {
  var chunk = arrayLike([
    ['a.txt', 'f', 100, 1700000000, 33188, null],
    ['sub', 'd', 0, 1700000000, 16877, null]
  ]);
  assert.equal(Array.isArray(chunk), false);
  var decoded = Model.decodeEntries(chunk, '/home/u');
  assert.equal(decoded.length, 2);
  assert.equal(decoded[0].name, 'a.txt');
  assert.equal(decoded[0].path, '/home/u/a.txt');
  assert.equal(decoded[1].isDir, true);
});

test('decodeEntry classifies kinds correctly', function () {
  var file = Model.decodeEntry(['f.txt', 'f', 10, 0, 33188, null], '/d');
  var dir = Model.decodeEntry(['dir', 'd', 0, 0, 16877, null], '/d');
  var symDir = Model.decodeEntry(['sd', 'L', 0, 0, 41453, '/target'], '/d');
  var symFile = Model.decodeEntry(['sf', 'l', 0, 0, 41471, '/target'], '/d');
  var broken = Model.decodeEntry(['bl', 'b', 0, 0, 41471, '/missing'], '/d');
  var exec = Model.decodeEntry(['run.sh', 'f', 10, 0, 33261, null], '/d');
  var other = Model.decodeEntry(['sock', 'o', 0, 0, 49663, null], '/d');

  assert.equal(file.isDir, false);
  assert.equal(dir.isDir, true);
  assert.equal(symDir.isDir, true);
  assert.equal(symDir.isLink, true);
  assert.equal(symFile.isDir, false);
  assert.equal(symFile.isLink, true);
  assert.equal(broken.isBroken, true);
  assert.equal(broken.isLink, true);
  assert.equal(exec.isExec, true);
  assert.equal(other.isDir, false);
});

test('ext is lowercased without the dot and empty for dotfiles with no second dot', function () {
  assert.equal(Model.decodeEntry(['Archive.TAR.GZ', 'f', 1, 0, 33188, null], '/d').ext, 'gz');
  assert.equal(Model.decodeEntry(['.bashrc', 'f', 1, 0, 33188, null], '/d').ext, '');
  assert.equal(Model.decodeEntry(['.config.json', 'f', 1, 0, 33188, null], '/d').ext, 'json');
  assert.equal(Model.decodeEntry(['noext', 'f', 1, 0, 33188, null], '/d').ext, '');
  assert.equal(Model.decodeEntry(['trailing.', 'f', 1, 0, 33188, null], '/d').ext, '');
});

test('kindLabel priority and extension derived labels', function () {
  assert.equal(Model.kindLabel(Model.decodeEntry(['d', 'd', 0, 0, 16877, null], '/x')), 'Folder');
  assert.equal(Model.kindLabel(Model.decodeEntry(['l', 'l', 0, 0, 41471, '/t'], '/x')), 'Symlink');
  assert.equal(Model.kindLabel(Model.decodeEntry(['b', 'b', 0, 0, 41471, '/t'], '/x')), 'Broken link');
  assert.equal(Model.kindLabel(Model.decodeEntry(['run.sh', 'f', 1, 0, 33261, null], '/x')), 'Executable');
  assert.equal(Model.kindLabel(Model.decodeEntry(['pic.png', 'f', 1, 0, 33188, null], '/x')), 'PNG image');
  assert.equal(Model.kindLabel(Model.decodeEntry(['notes.txt', 'f', 1, 0, 33188, null], '/x')), 'Plain text');
  assert.equal(Model.kindLabel(Model.decodeEntry(['data.xyz', 'f', 1, 0, 33188, null], '/x')), 'Unknown');
});

test('categoryFor covers every category', function () {
  var mk = function (name, kind, mode) {
    return Model.decodeEntry([name, kind, 1, 0, mode, null], '/x');
  };
  assert.equal(Model.categoryFor(mk('d', 'd', 16877)), 'folder');
  assert.equal(Model.categoryFor(mk('l', 'l', 41471)), 'link');
  assert.equal(Model.categoryFor(Model.decodeEntry(['b', 'b', 0, 0, 41471, '/t'], '/x')), 'broken');
  assert.equal(Model.categoryFor(mk('a.png', 'f', 33188)), 'image');
  assert.equal(Model.categoryFor(mk('a.mp4', 'f', 33188)), 'video');
  assert.equal(Model.categoryFor(mk('a.mp3', 'f', 33188)), 'audio');
  assert.equal(Model.categoryFor(mk('a.zip', 'f', 33188)), 'archive');
  assert.equal(Model.categoryFor(mk('a.js', 'f', 33188)), 'code');
  assert.equal(Model.categoryFor(mk('a.txt', 'f', 33188)), 'document');
  assert.equal(Model.categoryFor(mk('a.pdf', 'f', 33188)), 'pdf');
  assert.equal(Model.categoryFor(mk('a.ttf', 'f', 33188)), 'font');
  assert.equal(Model.categoryFor(mk('run.sh', 'f', 33261)), 'executable');
  assert.equal(Model.categoryFor(mk('a.bin', 'f', 33188)), 'file');
});

test('totalSize and countSelected', function () {
  var entries = Model.decodeEntries([
    ['a', 'f', 10, 0, 33188, null],
    ['b', 'f', 20, 0, 33188, null]
  ], '/d');
  assert.equal(Model.totalSize(entries), 30);
  assert.equal(Model.countSelected({ a: true, b: false, c: true }), 2);
  assert.equal(Model.countSelected({}), 0);
});

test('sortIndicator returns a glyph only for the active column', function () {
  assert.equal(Model.sortIndicator('name', 'name', false), '▲');
  assert.equal(Model.sortIndicator('name', 'name', true), '▼');
  assert.equal(Model.sortIndicator('name', 'size', false), '');
});
