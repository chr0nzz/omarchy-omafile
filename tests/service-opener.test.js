'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function service(mime) {
  const source = fs.readFileSync(path.join(__dirname, '..', 'Service.qml'), 'utf8');
  const calls = [];
  const c = vm.createContext({});
  c.root = c;
  const match = source.match(/^  function setDefaultApp\([^]*?^  }/m);
  vm.runInContext(match[0], c);
  c.openerFor = (file, onResult) => { calls.push(['openerFor', file]); onResult({ mime: mime, handler: '' }); };
  c.setOpener = (type, handler) => calls.push(['setOpener', type, handler]);
  return { c, calls };
}

test('the default app is saved for the type the helper reports, through setopener', () => {
  const { c, calls } = service('text/markdown');
  c.setDefaultApp('/tmp/readme.md', 'org.gnome.TextEditor');
  assert.deepEqual(calls, [['openerFor', '/tmp/readme.md'], ['setOpener', 'text/markdown', 'org.gnome.TextEditor.desktop']]);
});

test('an unknown type reports an error and saves nothing', () => {
  const { c, calls } = service('');
  let error = null;
  c.setDefaultApp('/tmp/blob', 'viewer.desktop', null, (m) => { error = m.message; });
  assert.equal(error, 'unknown file type');
  assert.deepEqual(calls, [['openerFor', '/tmp/blob']]);
});
