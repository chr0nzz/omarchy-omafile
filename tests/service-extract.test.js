'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const loadModule = require('./load.js');

function service() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'Service.qml'), 'utf8');
  const requests = [];
  const c = vm.createContext({ transfers: [], Model: loadModule('Model.js'), Date });
  c.root = c;
  for (const name of ['extractArchive', 'compressPaths', 'updateTransfer', 'transferActive', 'cancelTransfer']) {
    const match = source.match(new RegExp('^  function ' + name + '\\([^]*?^  }', 'm'));
    vm.runInContext(match[0], c);
  }
  c.request = (payload, handlers) => { requests.push({ payload, handlers }); return 40 + requests.length; };
  c.cancel = (id) => requests.push({ cancelled: id });
  c.trimTransferHistory = () => {};
  return { c, requests };
}

test('an extraction is a transfer with progress, so it shows in the Transfers panel', () => {
  const { c, requests } = service();
  let result = null;
  const id = c.extractArchive('/home/me/Downloads/photos.zip', (m) => { result = m.path; });
  assert.equal(requests[0].payload.op, 'extract');
  assert.equal(c.transfers.length, 1);
  assert.equal(c.transfers[0].id, id);
  assert.equal(c.transfers[0].op, 'extract');
  assert.equal(c.transfers[0].label, 'photos.zip');
  assert.equal(c.transfers[0].dest, '/home/me/Downloads');
  assert.equal(c.transfers[0].state, 'running');
  requests[0].handlers.onData({ id, t: 'progress', bytes: 50, total: 200, files: 3, current: 'a.jpg', rate: 10 });
  assert.equal(c.transfers[0].bytes, 50);
  assert.equal(c.transfers[0].total, 200);
  assert.equal(c.transfers[0].files, 3);
  requests[0].handlers.onDone({ id, path: '/home/me/Downloads/photos' });
  assert.equal(c.transfers[0].state, 'done');
  assert.equal(c.transfers[0].result, '/home/me/Downloads/photos');
  assert.equal(result, '/home/me/Downloads/photos');
});

test('cancelling an extraction cancels the helper request and marks it cancelled', () => {
  const { c, requests } = service();
  let error = null;
  const id = c.extractArchive('/tmp/big.tar.xz', null, (m) => { error = m.code; });
  c.cancelTransfer(id);
  assert.deepEqual(requests[1], { cancelled: id });
  assert.equal(c.transfers[0].state, 'cancelled');
  requests[0].handlers.onError({ id, code: 'ECANCELED', message: 'cancelled' });
  assert.equal(c.transfers[0].state, 'cancelled');
  assert.equal(error, 'ECANCELED');
});

test('compressing is a transfer named after the archive', () => {
  const { c, requests } = service();
  let result = null;
  const id = c.compressPaths(['/home/me/photos', '/home/me/notes.txt'], 'Archive.zip', (m) => { result = m.path; });
  assert.deepEqual(JSON.parse(JSON.stringify(requests[0].payload)), { op: 'compress', paths: ['/home/me/photos', '/home/me/notes.txt'], name: 'Archive.zip' });
  assert.equal(c.transfers[0].op, 'compress');
  assert.equal(c.transfers[0].label, 'Archive.zip');
  assert.equal(c.transfers[0].dest, '/home/me');
  assert.equal(c.transfers[0].count, 2);
  requests[0].handlers.onData({ id, t: 'progress', bytes: 10, total: 40, files: 2 });
  assert.equal(c.transfers[0].bytes, 10);
  requests[0].handlers.onDone({ id, path: '/home/me/Archive.zip' });
  assert.equal(c.transfers[0].state, 'done');
  assert.equal(result, '/home/me/Archive.zip');
});
