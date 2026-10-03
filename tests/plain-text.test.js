'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var fs = require('node:fs');
var path = require('node:path');

var root = path.join(__dirname, '..');

function qmlFiles() {
  var out = [];
  ['.', 'components'].forEach(function (dir) {
    fs.readdirSync(path.join(root, dir)).forEach(function (name) {
      if (name.endsWith('.qml')) out.push(path.join(dir, name));
    });
  });
  return out;
}

function withoutStrings(line) {
  return line.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/'(?:[^'\\]|\\.)*'/g, "''");
}

function textBlocks(source) {
  var lines = source.split('\n');
  var blocks = [];
  for (var i = 0; i < lines.length; i++) {
    if (!/(^|[\s:])Text\s*\{\s*$/.test(lines[i])) continue;
    var depth = 0;
    var plain = false;
    for (var j = i; j < lines.length; j++) {
      var clean = withoutStrings(lines[j]);
      if (j > i && depth === 1 && /^\s*textFormat:\s*Text\.PlainText\s*$/.test(clean)) plain = true;
      for (var k = 0; k < clean.length; k++) {
        if (clean[k] === '{') depth++;
        else if (clean[k] === '}') depth--;
      }
      if (depth === 0) break;
    }
    blocks.push({ line: i + 1, plain: plain });
  }
  return blocks;
}

test('every Text renders plain text, so names and paths are never parsed as rich text', function () {
  var missing = [];
  var seen = 0;
  qmlFiles().forEach(function (file) {
    textBlocks(fs.readFileSync(path.join(root, file), 'utf8')).forEach(function (block) {
      seen++;
      if (!block.plain) missing.push(file + ':' + block.line);
    });
  });
  assert.ok(seen > 0, 'found Text elements to check');
  assert.deepEqual(missing, []);
});

test('the checker spots a Text without a plain text format', function () {
  var blocks = textBlocks('Item {\n  Text {\n    text: "{a}"\n    Text {\n      textFormat: Text.PlainText\n    }\n  }\n}\n');
  assert.deepEqual(blocks.map(function (b) { return b.plain; }), [false, true]);
});
