'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const Model = require('./load.js')('Model.js');

function service() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'Service.qml'), 'utf8');
  const requests = [];
  const c = vm.createContext({ Model, undoStack: [], redoStack: [], transfers: [], _transferOwners: {} });
  c.root = c;
  for (const name of ['beginTransfer', 'transferOwner', 'createdPairs', 'createdPaths', 'okPaths', 'trashNames',
    'moveBack', 'applyReverse', 'applyForward', 'recordUndo', 'makeLink']) {
    const match = source.match(new RegExp('^  function ' + name + '\\([^]*?^  }', 'm'));
    vm.runInContext(match[0], c);
  }
  c.request = (payload, handlers) => { requests.push({ payload, handlers }); return requests.length; };
  c.updateTransfer = () => {};
  c.trimTransferHistory = () => {};
  c.refreshTrash = () => {};
  return { c, requests };
}

const plain = value => JSON.parse(JSON.stringify(value));

test('undoing a Keep both copy trashes the new copy, never the original', () => {
  const { c, requests } = service();
  c.beginTransfer('copy', ['/src/a.txt', '/src/b.txt'], '/dest', 'ask', null);
  requests[0].handlers.onDone({ id: 1, copied: 1, skipped: 1, created: [{ source: '/src/a.txt', path: '/dest/a (1).txt' }] });
  const entry = c.undoStack[0];
  assert.deepEqual(plain(entry.sources), ['/src/a.txt'], 'the skipped item is left out');
  c.applyReverse(entry, () => {}, () => {});
  assert.deepEqual(plain(requests[1].payload), { op: 'trash', paths: ['/dest/a (1).txt'] });
});

test('a merged or fully skipped transfer records nothing to undo', () => {
  const { c, requests } = service();
  c.beginTransfer('move', ['/src/dir'], '/dest', 'ask', null);
  requests[0].handlers.onDone({ id: 1, copied: 4, skipped: 0, created: [] });
  assert.equal(c.undoStack.length, 0);
});

test('undoing a move sends each item back to its own folder and redo uses where it landed', () => {
  const { c, requests } = service();
  c.beginTransfer('move', ['/one/a', '/two/b'], '/dest', 'ask', null);
  requests[0].handlers.onDone({ id: 1, copied: 2, created: [{ source: '/one/a', path: '/dest/a' }, { source: '/two/b', path: '/dest/b' }] });
  const entry = c.undoStack[0];
  let done = false;
  c.applyReverse(entry, () => { done = true; }, () => {});
  assert.deepEqual(plain(requests.slice(1).map(r => r.payload)), [
    { op: 'move', sources: ['/dest/a'], dest: '/one', conflict: 'rename' },
    { op: 'move', sources: ['/dest/b'], dest: '/two', conflict: 'rename' }
  ]);
  requests[1].handlers.onDone({ created: [{ source: '/dest/a', path: '/one/a (1)' }] });
  assert.equal(done, false);
  requests[2].handlers.onDone({ created: [{ source: '/dest/b', path: '/two/b' }] });
  assert.equal(done, true);
  c.applyForward(entry, () => {}, () => {});
  assert.deepEqual(plain(requests[3].payload.sources), ['/one/a (1)', '/two/b'], 'redo moves what the undo put back');
});

test('the window that started a transfer owns its conflicts', () => {
  const { c, requests } = service();
  const owner = { name: 'window 2' };
  c.beginTransfer('copy', ['/a'], '/dest', 'ask', owner);
  assert.equal(c.transferOwner(1), owner);
  requests[0].handlers.onError({ id: 1, code: 'ECANCELED' });
  assert.equal(c.transferOwner(1), null);
});

test('a new link undoes to the trash and redoes as the same link', () => {
  const { c, requests } = service();
  c.makeLink('/dest/shortcut', '/home/me/notes.txt', () => {}, () => {});
  requests[0].handlers.onDone({});
  assert.deepEqual(plain(requests[0].payload), { op: 'symlink', target: '/home/me/notes.txt', path: '/dest/shortcut' });
  const entry = c.undoStack[0];
  assert.equal(entry.label, 'New link');
  c.applyReverse(entry, () => {}, () => {});
  assert.deepEqual(plain(requests[1].payload), { op: 'trash', paths: ['/dest/shortcut'] });
  c.applyForward(entry, () => {}, () => {});
  assert.deepEqual(plain(requests[2].payload), { op: 'symlink', target: '/home/me/notes.txt', path: '/dest/shortcut' },
    'redo rebuilds a link, not an empty file');
});
