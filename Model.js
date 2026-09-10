var monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

var imageExtSet = toSet(['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif', 'heic', 'avif']);
var videoExtSet = toSet(['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', 'mpg', 'mpeg']);
var audioExtSet = toSet(['mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'wma', 'opus']);
var archiveExtSet = toSet(['zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'zst', 'tgz']);
var codeExtSet = toSet(['js', 'jsx', 'ts', 'tsx', 'py', 'rb', 'go', 'rs', 'c', 'h', 'cpp', 'hpp', 'java', 'kt', 'swift', 'sh', 'json', 'yaml', 'yml', 'toml', 'xml', 'html', 'css', 'scss', 'sql', 'lua', 'vim']);
var documentExtSet = toSet(['doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'xls', 'xlsx', 'csv', 'ppt', 'pptx']);
var fontExtSet = toSet(['ttf', 'otf', 'woff', 'woff2']);

var extLabels = {
  png: 'PNG image', jpg: 'JPEG image', jpeg: 'JPEG image', gif: 'GIF image', bmp: 'Bitmap image',
  webp: 'WebP image', svg: 'SVG image', ico: 'Icon image', tiff: 'TIFF image', tif: 'TIFF image',
  heic: 'HEIC image', avif: 'AVIF image',
  mp4: 'MP4 video', mkv: 'Matroska video', avi: 'AVI video', mov: 'QuickTime video', webm: 'WebM video',
  flv: 'Flash video', wmv: 'WMV video', m4v: 'MPEG-4 video', mpg: 'MPEG video', mpeg: 'MPEG video',
  mp3: 'MP3 audio', wav: 'WAV audio', flac: 'FLAC audio', ogg: 'Ogg audio', m4a: 'AAC audio',
  aac: 'AAC audio', wma: 'WMA audio', opus: 'Opus audio',
  zip: 'ZIP archive', tar: 'Tar archive', gz: 'Gzip archive', bz2: 'Bzip2 archive', xz: 'XZ archive',
  '7z': '7-Zip archive', rar: 'RAR archive', zst: 'Zstd archive', tgz: 'Gzip archive',
  js: 'JavaScript source', jsx: 'JavaScript source', ts: 'TypeScript source', tsx: 'TypeScript source',
  py: 'Python source', rb: 'Ruby source', go: 'Go source', rs: 'Rust source', c: 'C source',
  h: 'C header', cpp: 'C++ source', hpp: 'C++ header', java: 'Java source', kt: 'Kotlin source',
  swift: 'Swift source', sh: 'Shell script', json: 'JSON data', yaml: 'YAML data', yml: 'YAML data',
  toml: 'TOML data', xml: 'XML data', html: 'HTML document', css: 'CSS stylesheet', scss: 'SCSS stylesheet',
  sql: 'SQL source', lua: 'Lua source', vim: 'Vim script',
  md: 'Markdown document', txt: 'Plain text', rtf: 'Rich text',
  doc: 'Word document', docx: 'Word document', odt: 'OpenDocument text',
  xls: 'Excel spreadsheet', xlsx: 'Excel spreadsheet', csv: 'CSV data',
  ppt: 'PowerPoint presentation', pptx: 'PowerPoint presentation',
  pdf: 'PDF document',
  ttf: 'TrueType font', otf: 'OpenType font', woff: 'Web font', woff2: 'Web font'
};

function toSet(arr) {
  var o = {};
  for (var i = 0; i < arr.length; i++) o[arr[i]] = true;
  return o;
}

function pad2(n) {
  return (n < 10 ? '0' : '') + n;
}

function extOf(name) {
  var idx = name.lastIndexOf('.');
  if (idx <= 0) return '';
  if (idx === name.length - 1) return '';
  return name.slice(idx + 1).toLowerCase();
}

function decodeEntry(arr, dirPath) {
  var name = arr[0];
  var kind = arr[1];
  var size = arr[2];
  var mtime = arr[3];
  var mode = arr[4];
  var linkTarget = arr.length > 5 && arr[5] !== undefined ? arr[5] : null;
  var isDir = kind === 'd' || kind === 'L';
  var isLink = kind === 'L' || kind === 'l' || kind === 'b';
  var isBroken = kind === 'b';
  var modeNum = Number(mode) || 0;
  var isExec = !isDir && !isLink && (modeNum & 73) !== 0;
  var isHidden = typeof name === 'string' && name.charAt(0) === '.';

  return {
    name: name,
    kind: kind,
    size: size,
    mtime: mtime,
    mode: mode,
    linkTarget: linkTarget,
    path: (arr.length > 6 && typeof arr[6] === 'string' && arr[6].length > 0) ? arr[6] : joinPath(dirPath, name),
    isDir: isDir,
    isLink: isLink,
    isBroken: isBroken,
    isExec: isExec,
    isHidden: isHidden,
    ext: extOf(String(name))
  };
}

function decodeEntries(chunk, dirPath) {
  var out = [];
  if (!chunk) return out;
  var len = chunk.length || 0;
  for (var i = 0; i < len; i++) out.push(decodeEntry(chunk[i], dirPath));
  return out;
}

function splitNatural(s) {
  var out = [];
  var i = 0;
  var n = s.length;
  while (i < n) {
    var c = s.charAt(i);
    if (c >= '0' && c <= '9') {
      var j = i;
      while (j < n && s.charAt(j) >= '0' && s.charAt(j) <= '9') j++;
      out.push({ t: 1, v: s.slice(i, j) });
      i = j;
    } else {
      var k = i;
      while (k < n && !(s.charAt(k) >= '0' && s.charAt(k) <= '9')) k++;
      out.push({ t: 0, v: s.slice(i, k) });
      i = k;
    }
  }
  return out;
}

function naturalCompare(a, b) {
  var ax = splitNatural(String(a || '').toLowerCase());
  var bx = splitNatural(String(b || '').toLowerCase());
  var len = Math.max(ax.length, bx.length);
  for (var i = 0; i < len; i++) {
    var av = ax[i];
    var bv = bx[i];
    if (av === undefined) return -1;
    if (bv === undefined) return 1;
    if (av.t === 1 && bv.t === 1) {
      var an = parseInt(av.v, 10);
      var bn = parseInt(bv.v, 10);
      if (an !== bn) return an < bn ? -1 : 1;
    } else if (av.v !== bv.v) {
      return av.v < bv.v ? -1 : 1;
    }
  }
  return 0;
}

function sortEntries(entries, sortBy, descending, dirsFirst) {
  var list = (entries || []).slice();
  var dir = descending ? -1 : 1;
  list.sort(function (a, b) {
    if (dirsFirst) {
      var aDir = a.isDir ? 0 : 1;
      var bDir = b.isDir ? 0 : 1;
      if (aDir !== bDir) return aDir - bDir;
    }
    var cmp = 0;
    if (sortBy === 'size') {
      cmp = (Number(a.size) || 0) - (Number(b.size) || 0);
    } else if (sortBy === 'modified') {
      cmp = (Number(a.mtime) || 0) - (Number(b.mtime) || 0);
    } else if (sortBy === 'type') {
      cmp = naturalCompare(kindLabel(a), kindLabel(b));
      if (cmp === 0) cmp = naturalCompare(a.name, b.name);
    } else if (sortBy === 'ext') {
      cmp = naturalCompare(a.ext || '', b.ext || '');
      if (cmp === 0) cmp = naturalCompare(a.name, b.name);
    } else {
      cmp = naturalCompare(a.name, b.name);
    }
    return cmp * dir;
  });
  return list;
}

function filterEntries(entries, query, showHidden) {
  var q = String(query || '').toLowerCase();
  var list = entries || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var e = list[i];
    if (!showHidden && e.isHidden) continue;
    if (q === '' || String(e.name).toLowerCase().indexOf(q) !== -1) out.push(e);
  }
  return out;
}

function formatSize(bytes) {
  var n = Number(bytes) || 0;
  if (n < 0) n = 0;
  if (n < 1024) return Math.round(n) + ' B';
  var units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  var value = n / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value = value / 1024;
    i++;
  }
  return value.toFixed(1) + ' ' + units[i];
}

function formatCount(n, singular, plural) {
  var count = Number(n) || 0;
  return count + ' ' + (count === 1 ? singular : plural);
}

function formatDate(mtimeSeconds, nowMs) {
  var d = new Date(Number(mtimeSeconds) * 1000);
  var now = new Date(Number(nowMs));
  var sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
  if (sameDay) return pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  var yest = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  var isYesterday = d.getFullYear() === yest.getFullYear() && d.getMonth() === yest.getMonth() && d.getDate() === yest.getDate();
  if (isYesterday) return 'Yesterday';
  if (d.getFullYear() === now.getFullYear()) return monthNames[d.getMonth()] + ' ' + d.getDate();
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}

function formatFullDate(mtimeSeconds) {
  var d = new Date(Number(mtimeSeconds) * 1000);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' +
    pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

function formatMode(mode) {
  var m = Number(mode) || 0;
  var fmt = m & 61440;
  var typeChar = '?';
  if (fmt === 16384) typeChar = 'd';
  else if (fmt === 32768) typeChar = '-';
  else if (fmt === 40960) typeChar = 'l';
  else if (fmt === 8192) typeChar = 'c';
  else if (fmt === 24576) typeChar = 'b';
  else if (fmt === 4096) typeChar = 'p';
  else if (fmt === 49152) typeChar = 's';

  var tiers = [
    { r: 256, w: 128, x: 64, special: 2048, on: 's', off: 'S' },
    { r: 32, w: 16, x: 8, special: 1024, on: 's', off: 'S' },
    { r: 4, w: 2, x: 1, special: 512, on: 't', off: 'T' }
  ];
  var perms = '';
  for (var i = 0; i < tiers.length; i++) {
    var t = tiers[i];
    perms += (m & t.r) ? 'r' : '-';
    perms += (m & t.w) ? 'w' : '-';
    if (m & t.special) perms += (m & t.x) ? t.on : t.off;
    else perms += (m & t.x) ? 'x' : '-';
  }
  return typeChar + perms;
}

function formatRate(bytesPerSecond) {
  return formatSize(bytesPerSecond) + '/s';
}

function formatEta(seconds) {
  var s = Number(seconds);
  if (!isFinite(s) || s < 0) return '--';
  s = Math.round(s);
  if (s < 60) return s + 's';
  if (s < 3600) {
    var m = Math.floor(s / 60);
    var r = s % 60;
    return m + 'm ' + pad2(r) + 's';
  }
  var h = Math.floor(s / 3600);
  var mm = Math.floor((s % 3600) / 60);
  return h + 'h ' + pad2(mm) + 'm';
}

function basename(path) {
  var p = String(path || '').replace(/\/+$/, '');
  var idx = p.lastIndexOf('/');
  if (idx === -1) return p;
  return p.slice(idx + 1);
}

function dirname(path) {
  var p = String(path || '').replace(/\/+$/, '');
  var idx = p.lastIndexOf('/');
  if (idx <= 0) return '/';
  return p.slice(0, idx);
}

function joinPath(dir, name) {
  var d = String(dir || '');
  if (d === '') d = '/';
  if (d.charAt(d.length - 1) === '/') return d + name;
  return d + '/' + name;
}

function normalizePath(path) {
  var p = String(path || '');
  if (p === '') return '/';
  var absolute = p.charAt(0) === '/';
  var parts = p.split('/');
  var stack = [];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i];
    if (part === '' || part === '.') continue;
    if (part === '..') {
      if (stack.length > 0 && stack[stack.length - 1] !== '..') stack.pop();
      else if (!absolute) stack.push('..');
      continue;
    }
    stack.push(part);
  }
  if (absolute) return '/' + stack.join('/');
  var joined = stack.join('/');
  return joined === '' ? '.' : joined;
}

function parentPath(path) {
  var p = normalizePath(path);
  if (p === '/') return '/';
  var idx = p.lastIndexOf('/');
  if (idx <= 0) return '/';
  return p.slice(0, idx);
}

function expandTilde(path, homePath) {
  var p = String(path || '');
  var home = String(homePath || '');
  if (p === '~') return home || '/';
  if (p.indexOf('~/') === 0) return home + p.slice(1);
  return p;
}

function collapseTilde(path, homePath) {
  var p = String(path || '');
  var home = String(homePath || '');
  if (home === '') return p;
  var h = home.charAt(home.length - 1) === '/' ? home.slice(0, -1) : home;
  if (h === '') return p;
  if (p === h) return '~';
  if (p.indexOf(h + '/') === 0) return '~' + p.slice(h.length);
  return p;
}

function breadcrumbs(path) {
  var p = normalizePath(path);
  var out = [{ label: '/', path: '/' }];
  if (p === '/') return out;
  var parts = p.split('/');
  var cur = '';
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i];
    if (part === '') continue;
    cur = cur + '/' + part;
    out.push({ label: part, path: cur });
  }
  return out;
}

function isAncestor(ancestorPath, path) {
  var a = normalizePath(ancestorPath);
  var p = normalizePath(path);
  if (a === p) return false;
  if (a === '/') return true;
  return p.indexOf(a + '/') === 0;
}

function commonPrefix(a, b) {
  var n = Math.min(a.length, b.length);
  var i = 0;
  while (i < n && a.charAt(i) === b.charAt(i)) i++;
  return a.slice(0, i);
}

function completePath(partial, names) {
  var p = String(partial || '');
  var list = names || [];
  var matches = [];
  for (var i = 0; i < list.length; i++) {
    if (String(list[i]).indexOf(p) === 0) matches.push(list[i]);
  }
  if (matches.length === 0) return p;
  var prefix = matches[0];
  for (var j = 1; j < matches.length; j++) {
    prefix = commonPrefix(prefix, matches[j]);
    if (prefix.length <= p.length) break;
  }
  return prefix.length > p.length ? prefix : p;
}

function uniqueName(name, existingNames) {
  var existing = {};
  var list = existingNames || [];
  for (var i = 0; i < list.length; i++) existing[list[i]] = true;
  if (!existing[name]) return name;
  var dot = name.lastIndexOf('.');
  var base = name;
  var ext = '';
  if (dot > 0 && dot < name.length - 1) {
    base = name.slice(0, dot);
    ext = name.slice(dot);
  }
  var candidate = base + ' (copy)' + ext;
  var n = 2;
  while (existing[candidate]) {
    candidate = base + ' (copy ' + n + ')' + ext;
    n++;
  }
  return candidate;
}

function pasteTargetName(name, existingNames) {
  return uniqueName(name, existingNames);
}

function extensionLabel(ext) {
  var e = String(ext || '').toLowerCase();
  if (e === '') return 'Unknown';
  return extLabels[e] || 'Unknown';
}

function kindLabel(entry) {
  if (!entry) return 'Unknown';
  if (entry.isBroken) return 'Broken link';
  if (entry.isLink) return 'Symlink';
  if (entry.isDir) return 'Folder';
  if (entry.isExec) return 'Executable';
  return extensionLabel(entry.ext);
}

function categoryFor(entry) {
  if (!entry) return 'file';
  if (entry.isBroken) return 'broken';
  if (entry.isLink) return 'link';
  if (entry.isDir) return 'folder';
  if (entry.isExec) return 'executable';
  var ext = String(entry.ext || '').toLowerCase();
  if (ext === 'pdf') return 'pdf';
  if (imageExtSet[ext]) return 'image';
  if (videoExtSet[ext]) return 'video';
  if (audioExtSet[ext]) return 'audio';
  if (archiveExtSet[ext]) return 'archive';
  if (codeExtSet[ext]) return 'code';
  if (documentExtSet[ext]) return 'document';
  if (fontExtSet[ext]) return 'font';
  return 'file';
}

function totalSize(entries) {
  var list = entries || [];
  var sum = 0;
  for (var i = 0; i < list.length; i++) sum += Number(list[i].size) || 0;
  return sum;
}

function countSelected(selectionObject) {
  var obj = selectionObject || {};
  var n = 0;
  for (var k in obj) if (obj[k]) n++;
  return n;
}

function sortIndicator(sortBy, column, descending) {
  if (sortBy !== column) return '';
  return descending ? '▼' : '▲';
}

function rawName(row) {
  return row[0];
}

function rawIsDir(row) {
  return row[1] === 'd' || row[1] === 'L';
}

function filterRaw(rows, query) {
  var needle = String(query || '').toLowerCase();
  if (!needle) {
    var all = [];
    for (var a = 0; a < rows.length; a++) all.push(rows[a]);
    return all;
  }
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    if (String(rows[i][0]).toLowerCase().indexOf(needle) >= 0) out.push(rows[i]);
  }
  return out;
}

function isDefaultOrder(sortBy, descending, dirsFirst) {
  return sortBy === 'name' && !descending && dirsFirst;
}

function sortRaw(rows, sortBy, descending, dirsFirst) {
  var out = [];
  for (var i = 0; i < rows.length; i++) out.push(rows[i]);
  var direction = descending ? -1 : 1;
  out.sort(function (a, b) {
    if (dirsFirst) {
      var ad = rawIsDir(a) ? 0 : 1;
      var bd = rawIsDir(b) ? 0 : 1;
      if (ad !== bd) return ad - bd;
    }
    var result = 0;
    if (sortBy === 'size') result = (Number(a[2]) || 0) - (Number(b[2]) || 0);
    else if (sortBy === 'modified') result = (Number(a[3]) || 0) - (Number(b[3]) || 0);
    else if (sortBy === 'type' || sortBy === 'ext') {
      var ae = extOf(String(a[0]));
      var be = extOf(String(b[0]));
      result = ae < be ? -1 : (ae > be ? 1 : 0);
    }
    if (result === 0) return naturalCompare(String(a[0]), String(b[0])) * direction;
    return result * direction;
  });
  return out;
}
