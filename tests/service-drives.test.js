'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function service() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'Service.qml'), 'utf8');
  const c = vm.createContext({ JSON });
  let drives = [];
  let assigned = 0;
  Object.defineProperty(c, 'drives', { get: () => drives, set: (v) => { drives = v; assigned++; } });
  c.root = c;
  const match = source.match(/^  function refreshDrives\([^]*?^  }/m);
  vm.runInContext(match[0], c);
  let reply = [];
  c.request = (payload, handlers) => handlers.onData({ t: 'drives', drives: reply });
  return { c, setReply: (list) => { reply = list; }, assigned: () => assigned };
}

test('an unchanged drive list is not reassigned, so the sidebar is not rebuilt mid drag', () => {
  const s = service();
  s.setReply([{ path: '/dev/sdb1', mount: '/run/media/me/Stick' }]);
  s.c.refreshDrives();
  assert.equal(s.assigned(), 1);
  s.setReply([{ path: '/dev/sdb1', mount: '/run/media/me/Stick' }]);
  s.c.refreshDrives();
  assert.equal(s.assigned(), 1, 'same drives, no change');
  s.setReply([{ path: '/dev/sdb1', mount: '' }]);
  s.c.refreshDrives();
  assert.equal(s.assigned(), 2, 'a real change still updates');
});
