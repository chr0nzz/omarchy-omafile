'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function service(saved = {}) {
  const source = fs.readFileSync(path.join(__dirname, '..', 'Service.qml'), 'utf8');
  const requests = [];
  const writes = [];
  const context = vm.createContext({
    pinned: [], bookmarkLabels: {}, bookmarksMigrated: false, bookmarksLoaded: false,
    bookmarksDirty: false, bookmarksError: '', _legacyPinned: [], _bookmarkWatchId: 0,
    _bookmarkReadPending: false, _bookmarkWritePending: false, _bookmarkRevision: 0,
    _bookmarkGeneration: 0, _stateLoaded: false, recent: [], hiddenDrives: [], servers: [],
    serverSettings: {}, folderViews: {}, previousFileManager: '', session: null, _queue: [], _pending: {},
    helperRestarts: 0, helperReady: true, helperError: '', _thumbWaiting: {},
    restartTimer: { restart() {} }, bookmarkReloadTimer: { restart() {} },
    stateFile: { setText(text) { writes.push(JSON.parse(text)); } },
    Model: { basename(value) { return path.basename(value); } }
  });
  context.root = context;
  for (const match of source.matchAll(/^  function \w+\([^]*?^  }/gm)) {
    vm.runInContext(match[0], context);
  }
  context.request = (payload, handlers) => { requests.push({ payload, handlers }); return requests.length; };
  context.watchDirectory = () => 77;
  context.loadState(JSON.stringify(saved));
  return { context, requests, writes };
}

function read(request, items) {
  request.handlers.onData({ t: 'bookmarks', items, dir: '/gtk' });
  request.handlers.onDone({ t: 'done' });
}

const plain = value => JSON.parse(JSON.stringify(value));

test('migration keeps local backup until GTK write is acknowledged', () => {
  const { context: c, requests, writes } = service({ pinned: ['/legacy'] });
  c.persist();
  assert.deepEqual(writes.at(-1).pinned, ['/legacy']);
  requests[0].handlers.onData({ t: 'bookmarks', items: [{ path: '/gtk' }] });
  assert.equal(c.bookmarksMigrated, false);
  assert.equal(requests.length, 1);
  requests[0].handlers.onDone({ t: 'done' });
  assert.deepEqual(plain(requests[1].payload.items), [{ path: '/gtk', label: '' }, { path: '/legacy', label: '' }]);
  assert.equal(writes.at(-1).bookmarksMigrated, false);
  assert.deepEqual(writes.at(-1).pinned, ['/gtk', '/legacy']);
  requests[1].handlers.onDone({ t: 'done' });
  assert.equal(writes.at(-1).bookmarksMigrated, true);
  assert.equal(writes.at(-1).bookmarksDirty, false);
});

test('read error retains legacy bookmarks and surfaces failure', () => {
  const { context: c, requests, writes } = service({ pinned: ['/legacy'] });
  requests[0].handlers.onError({ message: 'Permission denied' });
  c.persist();
  assert.match(c.bookmarksError, /Permission denied/);
  assert.equal(c.bookmarksMigrated, false);
  assert.deepEqual(writes.at(-1).pinned, ['/legacy']);
  assert.equal(requests.length, 1);
});

test('write failure remains recoverable across a full service restart', () => {
  const first = service({ pinned: ['/legacy'] });
  read(first.requests[0], [{ path: '/gtk' }]);
  first.requests[1].handlers.onError({ message: 'Read-only file system' });
  assert.match(first.context.bookmarksError, /Read-only/);
  const second = service(first.writes.at(-1));
  read(second.requests[0], [{ path: '/gtk' }]);
  assert.deepEqual(plain(second.requests[1].payload.items).map(i => i.path), ['/gtk', '/legacy']);
  assert.equal(second.context.bookmarksMigrated, false);
  second.requests[1].handlers.onDone({ t: 'done' });
  assert.equal(second.context.bookmarksMigrated, true);
});

test('helper restart rejects stale acknowledgements and restores bookmark watch', () => {
  const { context: c, requests } = service({ pinned: ['/legacy'] });
  read(requests[0], []);
  c.handleHelperExit();
  assert.match(c.bookmarksError, /helper stopped/);
  assert.equal(c._bookmarkWatchId, 0);
  requests[1].handlers.onDone({ t: 'done' });
  assert.equal(c.bookmarksMigrated, false);
  c.refreshBookmarks();
  read(requests[2], []);
  assert.equal(c._bookmarkWatchId, 77);
  requests[3].handlers.onDone({ t: 'done' });
  assert.equal(c.bookmarksMigrated, true);
});

test('rapid edits serialize writes and stale reads cannot overwrite edits', () => {
  const { context: c, requests, writes } = service({ pinned: ['/legacy'] });
  c.addBookmarks(['/new']);
  read(requests[0], [{ path: '/gtk' }]);
  assert.equal(requests[1].payload.op, 'bookmarks');
  read(requests[1], [{ path: '/gtk' }]);
  assert.deepEqual(plain(c.pinned), ['/gtk', '/legacy', '/new']);
  c.renameBookmark('/new', 'New label');
  assert.equal(requests.length, 3);
  requests[2].handlers.onDone({ t: 'done' });
  assert.equal(c.bookmarksDirty, true);
  assert.equal(requests[3].payload.items.at(-1).label, 'New label');
  requests[3].handlers.onDone({ t: 'done' });
  assert.equal(writes.at(-1).bookmarksDirty, false);
});

test('pending removal survives restart without reintroducing GTK entry', () => {
  const { context: c, requests, writes } = service({ bookmarksMigrated: true, pinned: ['/keep', '/remove'] });
  read(requests[0], [{ path: '/keep' }, { path: '/remove' }]);
  c.togglePinned('/remove');
  requests[1].handlers.onError({ message: 'write failed' });
  const next = service(writes.at(-1));
  read(next.requests[0], [{ path: '/keep' }, { path: '/remove' }]);
  assert.deepEqual(plain(next.requests[1].payload.items), [{ path: '/keep', label: '' }]);
});

test('folder views are saved with the state and read back after a restart', () => {
  const first = service({});
  first.context.folderViews = { '/photos': 'gallery' };
  first.context.persist();
  const saved = first.writes.at(-1);
  assert.deepEqual(plain(saved.folderViews), { '/photos': 'gallery' });
  const second = service(saved);
  assert.deepEqual(plain(second.context.folderViews), { '/photos': 'gallery' });
});
