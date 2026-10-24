var monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

var imageExtSet = toSet(['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif', 'heic', 'avif', 'jxl']);
var videoExtSet = toSet(['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', 'mpg', 'mpeg']);
var audioExtSet = toSet(['mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'wma', 'opus']);
var archiveExtSet = toSet(['zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'zst', 'tgz']);
var codeExtSet = toSet(['js', 'jsx', 'ts', 'tsx', 'py', 'rb', 'go', 'rs', 'c', 'h', 'cpp', 'hpp', 'java', 'kt', 'swift', 'sh', 'json', 'yaml', 'yml', 'toml', 'xml', 'html', 'css', 'scss', 'sql', 'lua', 'vim']);
var documentExtSet = toSet(['doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'xls', 'xlsx', 'csv', 'ppt', 'pptx']);
var fontExtSet = toSet(['ttf', 'otf', 'woff', 'woff2']);

var extLabels = {
  png: 'PNG image', jpg: 'JPEG image', jpeg: 'JPEG image', gif: 'GIF image', bmp: 'Bitmap image',
  webp: 'WebP image', jxl: 'JPEG XL image', svg: 'SVG image', ico: 'Icon image', tiff: 'TIFF image', tif: 'TIFF image',
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

var naturalParts = /[0-9]+|[^0-9]+/g;

function naturalKey(s) {
  var pieces = String(s || '').toLowerCase().match(naturalParts) || [];
  var parts = [];
  for (var i = 0; i < pieces.length; i++) {
    var v = pieces[i];
    var c = v.charCodeAt(0);
    if (c >= 48 && c <= 57) parts.push({ t: 1, v: v, n: parseInt(v, 10) });
    else parts.push({ t: 0, v: v });
  }
  return parts;
}

function compareNaturalKeys(ax, bx) {
  var len = Math.max(ax.length, bx.length);
  for (var i = 0; i < len; i++) {
    var av = ax[i];
    var bv = bx[i];
    if (av === undefined) return -1;
    if (bv === undefined) return 1;
    if (av.t === 1 && bv.t === 1) {
      if (av.n !== bv.n) return av.n < bv.n ? -1 : 1;
    } else if (av.v !== bv.v) {
      return av.v < bv.v ? -1 : 1;
    }
  }
  return 0;
}

function naturalCompare(a, b) {
  return compareNaturalKeys(naturalKey(a), naturalKey(b));
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
  var secs = Number(mtimeSeconds) || 0;
  if (secs <= 0) return '';
  var d = new Date(secs * 1000);
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

function formatOctal(mode) {
  var bits = (Number(mode) || 0) & 4095;
  var text = bits.toString(8);
  while (text.length < 3) text = '0' + text;
  return text;
}

function formatExactSize(bytes) {
  var n = Math.max(0, Math.round(Number(bytes) || 0));
  var digits = String(n);
  var out = '';
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ',';
    out += digits.charAt(i);
  }
  return out + (n === 1 ? ' byte' : ' bytes');
}

function modeChange(oldMode, newMode) {
  var before = (Number(oldMode) || 0) & 4095;
  var after = (Number(newMode) || 0) & 4095;
  return { set: after & ~before, clear: before & ~after };
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

var extractSuffixes = ['.tar.gz', '.tar.xz', '.tar.bz2', '.tar.zst', '.tar.lz', '.tar', '.tgz', '.txz',
  '.tbz', '.tbz2', '.tzst', '.zip', '.7z', '.rar'];

function isPlainFileName(name) {
  if (typeof name !== 'string') return false;
  if (name === '' || name === '.' || name === '..') return false;
  return name.indexOf('/') < 0 && name.indexOf('\0') < 0;
}

function compressName(entries) {
  if (!entries || entries.length !== 1) return 'Archive';
  var entry = entries[0];
  var name = String(entry.name || '');
  if (entry.isDir) return name || 'Archive';
  var lower = name.toLowerCase();
  for (var i = 0; i < extractSuffixes.length; i++) {
    var suffix = extractSuffixes[i];
    if (lower.length > suffix.length && lower.slice(-suffix.length) === suffix) return name.slice(0, -suffix.length);
  }
  var dot = name.lastIndexOf('.');
  return dot > 0 ? name.slice(0, dot) : (name || 'Archive');
}

function isArchive(entry) {
  if (!entry || entry.isDir || entry.isBroken) return false;
  var lower = String(entry.name || '').toLowerCase();
  for (var i = 0; i < extractSuffixes.length; i++)
    if (lower.length > extractSuffixes[i].length && lower.slice(-extractSuffixes[i].length) === extractSuffixes[i]) return true;
  return false;
}

var editLimit = 1024 * 1024;
var notTextExtSet = toSet(['pdf', 'doc', 'docx', 'odt', 'ods', 'odp', 'xls', 'xlsx', 'ppt', 'pptx', 'epub',
  'iso', 'img', 'dmg', 'exe', 'dll', 'so', 'o', 'a', 'bin', 'dat', 'db', 'sqlite', 'sqlite3', 'class', 'jar',
  'pyc', 'deb', 'rpm', 'apk', 'msi', 'psd', 'xcf', 'blend', 'kra', 'ai', 'mobi', 'qcow2', 'vdi', 'wasm']);

function textEditable(entry) {
  if (!entry || entry.isDir || entry.isBroken) return false;
  if (entry.kind !== undefined && entry.kind !== 'f' && entry.kind !== 'l') return false;
  if ((Number(entry.size) || 0) > editLimit) return false;
  var ext = String(entry.ext || '').toLowerCase();
  return !imageExtSet[ext] && !videoExtSet[ext] && !audioExtSet[ext] && !archiveExtSet[ext]
    && !fontExtSet[ext] && !notTextExtSet[ext];
}

var previewSides = [1024, 2048, 4096, 7680];
var autoPreviewMax = 4096;

function previewSide(choice, screenPixels) {
  var fixed = Number(choice);
  if (previewSides.indexOf(fixed) >= 0) return fixed;
  var need = Number(screenPixels) || 0;
  for (var i = 0; i < previewSides.length; i++)
    if (previewSides[i] >= need || previewSides[i] >= autoPreviewMax) return previewSides[i];
  return autoPreviewMax;
}

var transcodePictureExts = toSet(['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'avif', 'jxl', 'bmp', 'tif', 'tiff']);
var transcodeVideoExts = toSet(['mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', 'mpg', 'mpeg', 'ts', 'flv']);

function transcodeKind(entry) {
  if (!entry || entry.isDir || entry.isBroken) return '';
  var ext = extOf(String(entry.name || ''));
  if (transcodePictureExts[ext]) return 'picture';
  if (transcodeVideoExts[ext]) return 'video';
  return '';
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
  var fromHome = p.charAt(0) === '~';
  var out = [fromHome ? { label: '~', path: '~' } : { label: '/', path: '/' }];
  if (p === '/' || p === '~') return out;
  var parts = p.split('/');
  var cur = fromHome ? '~' : '';
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i];
    if (part === '') continue;
    if (fromHome && i === 0 && part === '~') continue;
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

function parseServerUri(uri) {
  var m = /^([a-z][a-z0-9+.-]*):\/\/(?:([^@\/]*)@)?(\[[^\]]+\]|[^:\/?#]*)(?::(\d+))?(\/[^?#]*)?/i.exec(String(uri || '').trim());
  if (!m) return null;
  return { scheme: m[1].toLowerCase(), user: m[2] || '', host: (m[3] || '').toLowerCase(), port: m[4] || '', path: m[5] || '' };
}

function serverKey(user, host, port) {
  return (user ? user + '@' : '') + String(host || '').toLowerCase() + (port ? ':' + port : '');
}

function serverKeyOf(uri) {
  var p = parseServerUri(uri);
  return p ? serverKey(p.user, p.host, p.port) : String(uri || '');
}

function serverLabel(uri) {
  var p = parseServerUri(uri);
  if (!p || !p.host) return String(uri || '');
  return (p.user ? p.user + '@' : '') + p.host;
}

function fileUrlToPath(url) {
  var s = String(url || '');
  if (s.indexOf('file://') !== 0) return '';
  var rest = s.slice(7);
  if (rest.charAt(0) !== '/') {
    var slash = rest.indexOf('/');
    var host = slash < 0 ? rest : rest.slice(0, slash);
    if (host !== '' && host !== 'localhost') return '';
    rest = slash < 0 ? '/' : rest.slice(slash);
  }
  var cut = rest.search(/[?#]/);
  if (cut >= 0) rest = rest.slice(0, cut);
  try {
    return normalizePath(decodeURIComponent(rest));
  } catch (e) {
    return '';
  }
}

function localPathsFromUrls(urls) {
  var out = [];
  var seen = {};
  var list = urls || [];
  for (var i = 0; i < list.length; i++) {
    var p = fileUrlToPath(list[i]);
    if (p === '' || seen[p]) continue;
    seen[p] = true;
    out.push(p);
  }
  return out;
}

function selectionSummary(entries) {
  var list = entries || [];
  if (list.length === 0) return '';
  if (list.length === 1) {
    var one = list[0];
    return '\u201c' + one.name + '\u201d selected' + (one.isDir ? '' : ' (' + formatSize(Number(one.size) || 0) + ')');
  }
  var bytes = 0;
  var files = 0;
  var dirs = 0;
  for (var i = 0; i < list.length; i++) {
    if (list[i].isDir) dirs++;
    else {
      files++;
      bytes += Number(list[i].size) || 0;
    }
  }
  var text = formatCount(list.length, 'item selected', 'items selected');
  if (files > 0) text += ' (' + formatSize(bytes) + (dirs > 0 ? ' in ' + formatCount(files, 'file', 'files') : '') + ')';
  return text;
}

function trashRootOf(path, homeTrash) {
  var raw = String(path || '');
  if (raw === '' || raw.charAt(0) !== '/') return '';
  var p = normalizePath(raw);
  if (homeTrash) {
    var home = normalizePath(homeTrash);
    if (p === home || isAncestor(home, p)) return home;
  }
  var m = /^(.*\/\.Trash-\d+\/files)(\/|$)/.exec(p);
  return m ? m[1] : '';
}

function isTrashPath(path, homeTrash) {
  return trashRootOf(path, homeTrash) !== '';
}

function allInTrash(paths, homeTrash) {
  var list = paths || [];
  if (list.length === 0) return false;
  for (var i = 0; i < list.length; i++) {
    var root = trashRootOf(list[i], homeTrash);
    if (root === '' || root === normalizePath(list[i])) return false;
  }
  return true;
}

function trashItemNames(paths, homeTrash) {
  var list = paths || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var p = normalizePath(list[i]);
    var root = trashRootOf(p, homeTrash);
    if (root !== '' && root !== p && parentPath(p) === root) out.push(p.slice(root.length + 1));
  }
  return out;
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

function alwaysOpenLabel(entry) {
  var ext = String((entry && entry.ext) || '').toLowerCase();
  if (ext === '') return 'Always open this type of file with this app';
  var known = extensionLabel(ext);
  var pattern = '(*.' + ext + ')';
  return 'Always open ' + (known === 'Unknown' ? pattern : known + ' ' + pattern) + ' with this app';
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
  var byType = sortBy === 'type' || sortBy === 'ext';
  var items = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var name = String(row[0]);
    var value = 0;
    if (sortBy === 'size') value = Number(row[2]) || 0;
    else if (sortBy === 'modified') value = Number(row[3]) || 0;
    else if (byType) value = extOf(name);
    items.push({ row: row, dir: dirsFirst && rawIsDir(row) ? 0 : 1, value: value, key: naturalKey(name) });
  }
  var direction = descending ? -1 : 1;
  items.sort(function (a, b) {
    if (a.dir !== b.dir) return a.dir - b.dir;
    var result = byType ? (a.value < b.value ? -1 : (a.value > b.value ? 1 : 0)) : a.value - b.value;
    if (result === 0) return compareNaturalKeys(a.key, b.key) * direction;
    return result * direction;
  });
  var out = [];
  for (var j = 0; j < items.length; j++) out.push(items[j].row);
  return out;
}

var shellNames = { sh: true, bash: true, dash: true, zsh: true, ksh: true, mksh: true, ash: true, busybox: true };

function shellQuote(text) {
  return "'" + String(text).replace(/'/g, "'\\''") + "'";
}

function isShellScriptArg(args, index) {
  if (index < 2 || String(args[index - 1]) !== '-c') return false;
  for (var i = 0; i < index - 1; i++) {
    var word = String(args[i]);
    var base = word.substring(word.lastIndexOf('/') + 1);
    if (shellNames[base]) return true;
  }
  return false;
}

function expandFieldCodes(command, path) {
  var out = [];
  var target = path === undefined || path === null ? '' : String(path);
  var used = false;
  var length = command && command.length ? command.length : 0;
  for (var i = 0; i < length; i++) {
    var arg = String(command[i]);
    var inScript = isShellScriptArg(command, i);
    var built = '';
    for (var j = 0; j < arg.length; j++) {
      var ch = arg.charAt(j);
      if (ch !== '%') {
        built += ch;
        continue;
      }
      var code = arg.charAt(j + 1);
      if (code === '') {
        built += '%';
        continue;
      }
      j++;
      if (code === '%') {
        built += '%';
        continue;
      }
      if (code === 'f' || code === 'F' || code === 'u' || code === 'U') {
        built += inScript ? shellQuote(target) : target;
        used = true;
      }
    }
    if (built !== '') out.push(built);
  }
  if (out.length === 0) return [];
  if (!used) out.push(target);
  return out;
}

function takesFileList(command) {
  var list = false;
  var length = command && command.length ? command.length : 0;
  for (var i = 0; i < length; i++) {
    var arg = String(command[i]);
    for (var j = 0; j < arg.length; j++) {
      if (arg.charAt(j) !== '%') continue;
      var code = arg.charAt(j + 1);
      j++;
      if (code === 'f' || code === 'u') return false;
      if (code !== 'F' && code !== 'U') continue;
      if (arg !== '%' + code && !isShellScriptArg(command, i)) return false;
      list = true;
    }
  }
  return list;
}

function expandFieldCodesMulti(command, paths) {
  var targets = [];
  var count = paths && paths.length ? paths.length : 0;
  for (var p = 0; p < count; p++) targets.push(String(paths[p]));
  if (targets.length === 0) return [];
  if (targets.length === 1 || !takesFileList(command)) {
    var each = [];
    for (var t = 0; t < targets.length; t++) {
      var single = expandFieldCodes(command, targets[t]);
      if (single.length > 0) each.push(single);
    }
    return each;
  }
  var quoted = targets.map(shellQuote).join(' ');
  var out = [];
  for (var i = 0; i < command.length; i++) {
    var arg = String(command[i]);
    var inScript = isShellScriptArg(command, i);
    if (!inScript && (arg === '%F' || arg === '%U')) {
      out = out.concat(targets);
      continue;
    }
    var built = '';
    for (var j = 0; j < arg.length; j++) {
      var ch = arg.charAt(j);
      if (ch !== '%') {
        built += ch;
        continue;
      }
      var code = arg.charAt(j + 1);
      if (code === '') {
        built += '%';
        continue;
      }
      j++;
      if (code === '%') built += '%';
      else if (code === 'F' || code === 'U') built += quoted;
    }
    if (built !== '') out.push(built);
  }
  return out.length > 0 ? [out] : [];
}

function tokenizeCommand(text) {
  var source = text === undefined || text === null ? '' : String(text);
  var out = [];
  var current = '';
  var started = false;
  var quote = '';
  for (var i = 0; i < source.length; i++) {
    var ch = source.charAt(i);
    if (quote !== '') {
      if (ch === quote) {
        quote = '';
        continue;
      }
      if (quote === '"' && ch === '\\') {
        var escaped = source.charAt(i + 1);
        if (escaped === '"' || escaped === '\\' || escaped === '$' || escaped === '`') {
          current += escaped;
          i++;
          continue;
        }
      }
      current += ch;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      started = true;
      continue;
    }
    if (ch === '\\' && i + 1 < source.length) {
      current += source.charAt(i + 1);
      i++;
      started = true;
      continue;
    }
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      if (started) {
        out.push(current);
        current = '';
        started = false;
      }
      continue;
    }
    current += ch;
    started = true;
  }
  if (quote !== '') return [];
  if (started) out.push(current);
  return out;
}

var envAssignment = /^[A-Za-z_][A-Za-z0-9_]*=/;

function commandProgram(text) {
  var words = tokenizeCommand(text);
  for (var i = 0; i < words.length; i++) {
    if (envAssignment.test(words[i])) continue;
    return words[i];
  }
  return '';
}

function commandName(text) {
  return basename(commandProgram(text));
}

var knownEditors = [
  { id: 'code', name: 'VS Code', omarchy: true, terminal: false },
  { id: 'cursor', name: 'Cursor', omarchy: true, terminal: false },
  { id: 'zeditor', name: 'Zed', omarchy: true, terminal: false },
  { id: 'sublime_text', name: 'Sublime Text', omarchy: true, terminal: false },
  { id: 'emacs', name: 'Emacs', omarchy: true, terminal: false },
  { id: 'nvim', name: 'Neovim', omarchy: true, terminal: true },
  { id: 'vim', name: 'Vim', omarchy: true, terminal: true },
  { id: 'helix', name: 'Helix', omarchy: true, terminal: true },
  { id: 'nano', name: 'nano', omarchy: false, terminal: true },
  { id: 'micro', name: 'micro', omarchy: false, terminal: true }
];
var terminalEditors = toSet(['nvim', 'vim', 'vi', 'nano', 'micro', 'hx', 'helix', 'fresh', 'kak', 'emacsclient-nw']);

function knownEditor(id) {
  for (var i = 0; i < knownEditors.length; i++) if (knownEditors[i].id === id) return knownEditors[i];
  return null;
}

function editorName(id) {
  var known = knownEditor(String(id || ''));
  return known ? known.name : String(id || '');
}

function editorInTerminal(command) {
  return terminalEditors[commandName(command)] === true;
}

var omarchyAgentNames = {
  pi: 'Pi', omp: 'Oh My Pi', opencode: 'OpenCode', claude: 'Claude Code', codex: 'Codex', crush: 'Crush',
  grok: 'Grok', gemini: 'Gemini', openclaw: 'OpenClaw', hermes: 'Hermes', copilot: 'GitHub Copilot',
  'cursor-agent': 'Cursor CLI', muse: 'Muse Code'
};

function agentChoice(setting, omarchyAgent, omarchyFound, claudeFound) {
  var own = String(setting || '').trim();
  if (own) return { command: own, name: commandName(own) || own, source: 'own' };
  var picked = String(omarchyAgent || '');
  if (picked && omarchyFound) return { command: picked, name: omarchyAgentNames[picked] || picked, source: 'omarchy' };
  if (claudeFound) return { command: 'claude', name: 'Claude Code', source: 'claude' };
  return { command: '', name: '', source: '' };
}

var globLimit = 64;
var globCache = {};
var globCacheSize = 0;

function compileGlob(pattern) {
  var source = String(pattern || '').toLowerCase();
  if (source.length > globLimit) return null;
  if (globCache.hasOwnProperty(source)) return globCache[source];
  var tokens = [];
  for (var i = 0; i < source.length; i++) {
    var ch = source.charAt(i);
    if (ch === '*') {
      if (tokens.length === 0 || tokens[tokens.length - 1].type !== 'star') tokens.push({ type: 'star' });
    } else if (ch === '?') tokens.push({ type: 'any' });
    else if (ch === '[') {
      var close = source.indexOf(']', i + 2);
      if (close < 0) {
        tokens.push({ type: 'char', ch: '[' });
        continue;
      }
      var body = source.substring(i + 1, close);
      var negate = body.charAt(0) === '!' || body.charAt(0) === '^';
      if (negate) body = body.substring(1);
      var ranges = [];
      for (var k = 0; k < body.length; k++) {
        if (k + 2 < body.length && body.charAt(k + 1) === '-') {
          ranges.push([body.charAt(k), body.charAt(k + 2)]);
          k += 2;
        } else ranges.push([body.charAt(k), body.charAt(k)]);
      }
      tokens.push({ type: 'set', negate: negate, ranges: ranges });
      i = close;
    } else tokens.push({ type: 'char', ch: ch });
  }
  if (globCacheSize > 512) {
    globCache = {};
    globCacheSize = 0;
  }
  globCache[source] = tokens;
  globCacheSize++;
  return tokens;
}

function globTokenMatches(token, ch) {
  if (token.type === 'any') return true;
  if (token.type === 'char') return token.ch === ch;
  var hit = false;
  for (var i = 0; i < token.ranges.length && !hit; i++) {
    var lo = token.ranges[i][0];
    var hi = token.ranges[i][1];
    if (lo <= hi ? (ch >= lo && ch <= hi) : (ch >= hi && ch <= lo)) hit = true;
  }
  return token.negate ? !hit : hit;
}

function globMatch(pattern, name) {
  var tokens = compileGlob(pattern);
  if (!tokens) return false;
  var text = String(name || '').toLowerCase();
  var t = 0;
  var p = 0;
  var starAt = -1;
  var resume = 0;
  while (t < text.length) {
    if (p < tokens.length && tokens[p].type === 'star') {
      starAt = p++;
      resume = t;
    } else if (p < tokens.length && globTokenMatches(tokens[p], text.charAt(t))) {
      p++;
      t++;
    } else if (starAt >= 0) {
      p = starAt + 1;
      t = ++resume;
    } else return false;
  }
  while (p < tokens.length && tokens[p].type === 'star') p++;
  return p === tokens.length;
}

function matchesPatterns(name, patterns) {
  if (!patterns || !patterns.length) return true;
  var text = String(name || '');
  for (var i = 0; i < patterns.length; i++) {
    var p = String(patterns[i] || '');
    if (!p || p === '*' || p.indexOf('mime:') === 0) return true;
    if (globMatch(p, text)) return true;
  }
  return false;
}

function filterByPatterns(rows, patterns) {
  if (!patterns || !patterns.length) return rows;
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    if (rawIsDir(rows[i]) || matchesPatterns(rawName(rows[i]), patterns)) out.push(rows[i]);
  }
  return out;
}

var sortPresets = [
  { key: 'name-asc', label: 'A to Z', sortBy: 'name', descending: false },
  { key: 'name-desc', label: 'Z to A', sortBy: 'name', descending: true },
  { key: 'modified-desc', label: 'Last modified', sortBy: 'modified', descending: true },
  { key: 'modified-asc', label: 'First modified', sortBy: 'modified', descending: false },
  { key: 'size-desc', label: 'Largest first', sortBy: 'size', descending: true },
  { key: 'size-asc', label: 'Smallest first', sortBy: 'size', descending: false },
  { key: 'type-asc', label: 'Type', sortBy: 'type', descending: false }
];

function sortPreset(key) {
  for (var i = 0; i < sortPresets.length; i++) if (sortPresets[i].key === key) return sortPresets[i];
  return null;
}

function sortPresetKey(sortBy, descending) {
  return String(sortBy || 'name') + (descending ? '-desc' : '-asc');
}

var viewModes = [
  { key: 'list', label: 'List', glyph: 'list' },
  { key: 'grid', label: 'Grid', glyph: 'grid' },
  { key: 'compact', label: 'Compact', glyph: 'columns' },
  { key: 'gallery', label: 'Gallery', glyph: 'image' }
];

function isViewMode(key) {
  for (var i = 0; i < viewModes.length; i++) if (viewModes[i].key === key) return true;
  return false;
}

function normalizeViewMode(key) {
  return isViewMode(key) ? key : 'list';
}

var folderViewLimit = 500;

function folderViewFor(saved, path, fallback) {
  var view = saved ? saved[String(path || '')] : undefined;
  return isViewMode(view) ? view : normalizeViewMode(fallback);
}

function rememberFolderView(saved, path, view) {
  var key = String(path || '');
  var current = saved || {};
  if (key === '' || !isViewMode(view)) return current;
  var keys = Object.keys(current).filter(function (k) { return k !== key; });
  keys = keys.slice(Math.max(0, keys.length - (folderViewLimit - 1)));
  var out = {};
  for (var i = 0; i < keys.length; i++) out[keys[i]] = current[keys[i]];
  out[key] = view;
  return out;
}

function isImageName(name) {
  return !!imageExtSet[extOf(String(name || ''))];
}

var imagePreviewLimit = 1024 * 1024 * 1024;

function previewKind(entry) {
  if (!entry) return 'none';
  if (entry.isDir) return 'folder';
  if (entry.isBroken) return 'none';
  if (entry.kind !== 'f' && entry.kind !== 'l') return 'none';
  var ext = String(entry.ext || '').toLowerCase();
  if (imageExtSet[ext]) return (Number(entry.size) || 0) > imagePreviewLimit ? 'none' : 'image';
  if (audioExtSet[ext]) return 'audio';
  return 'text';
}

function outputVolume(sliderValue) {
  var v = Number(sliderValue) || 0;
  if (v <= 0) return 0;
  if (v > 0.99) return 1;
  return -Math.log(1 - v) / Math.log(100);
}

function formatDuration(ms) {
  var total = Math.floor((Number(ms) || 0) / 1000);
  if (total < 0) total = 0;
  var hours = Math.floor(total / 3600);
  var minutes = Math.floor((total % 3600) / 60);
  var seconds = total % 60;
  if (hours > 0) return hours + ':' + pad2(minutes) + ':' + pad2(seconds);
  return minutes + ':' + pad2(seconds);
}

function windowTitle(slot) {
  return slot > 1 ? 'Omafile ' + slot : 'Omafile';
}

function nextWindowSlot(slots) {
  var slot = 1;
  while (slots.indexOf(slot) >= 0) slot++;
  return slot;
}

function cascadeOffset(otherWindows) {
  return (Math.max(0, Number(otherWindows) || 0) % 8) * 40;
}

function wantsNewWindow(payloadJson) {
  try {
    var parsed = JSON.parse(String(payloadJson || ''));
    return !!parsed && parsed.newWindow === true;
  } catch (e) {
    return false;
  }
}

var placeOrderLimit = 100;

function orderPlaces(rows, order) {
  var rank = {};
  var saved = order || [];
  for (var i = 0; i < saved.length; i++) rank[String(saved[i])] = i;
  var movable = [];
  var fixed = [];
  for (var r = 0; r < rows.length; r++) {
    var id = rows[r].orderId;
    if (id) movable.push({ row: rows[r], rank: rank[id] !== undefined ? rank[id] : saved.length, at: r });
    else fixed.push(rows[r]);
  }
  movable.sort(function (a, b) { return a.rank - b.rank || a.at - b.at; });
  var out = [];
  for (var m = 0; m < movable.length; m++) out.push(movable[m].row);
  return out.concat(fixed);
}

function placeOrderIds(rows) {
  var ids = [];
  for (var i = 0; i < rows.length; i++) if (rows[i].orderId) ids.push(String(rows[i].orderId));
  return ids;
}

function movePlace(ids, id, index) {
  var from = ids.indexOf(id);
  if (from < 0) return ids.slice();
  var next = ids.slice();
  next.splice(from, 1);
  var to = Math.max(0, Math.min(next.length, index));
  next.splice(to, 0, id);
  return next;
}

function cleanPlaceOrder(value) {
  var out = {};
  if (!value || typeof value !== 'object' || Array.isArray(value)) return out;
  for (var key in value) {
    var list = value[key];
    if (!Array.isArray(list)) continue;
    var ids = [];
    for (var i = 0; i < list.length && ids.length < placeOrderLimit; i++)
      if (typeof list[i] === 'string' && list[i] !== '' && ids.indexOf(list[i]) < 0) ids.push(list[i]);
    if (ids.length > 0) out[key] = ids;
  }
  return out;
}

function rememberPlaceOrder(saved, ids) {
  var next = ids.slice();
  var old = saved || [];
  for (var i = 0; i < old.length; i++) {
    var id = String(old[i]);
    if (next.indexOf(id) >= 0) continue;
    next.splice(Math.min(i, next.length), 0, id);
  }
  return next.slice(0, placeOrderLimit);
}

function clampSectionOffset(tops, heights, from, offset) {
  var last = tops.length - 1;
  var min = tops[0] - tops[from];
  var max = tops[last] + heights[last] - tops[from] - heights[from];
  return Math.max(min, Math.min(max, offset));
}

function sectionDropIndex(tops, heights, from, offset) {
  var center = tops[from] + heights[from] / 2 + offset;
  var index = 0;
  for (var i = 0; i < tops.length; i++)
    if (i !== from && tops[i] + heights[i] / 2 < center) index++;
  return index;
}

function sectionSettleOffset(tops, heights, from, to) {
  if (to > from) return tops[to] + heights[to] - tops[from] - heights[from];
  if (to < from) return tops[to] - tops[from];
  return 0;
}

function sectionShift(heights, gap, from, to, index) {
  if (from < to && index > from && index <= to) return -(heights[from] + gap);
  if (from > to && index >= to && index < from) return heights[from] + gap;
  return 0;
}

function isWithin(path, root) {
  var p = String(path || '');
  var r = String(root || '');
  while (r.length > 1 && r.charAt(r.length - 1) === '/') r = r.substring(0, r.length - 1);
  if (!r || r === '/') return false;
  return p === r || p.indexOf(r + '/') === 0;
}

var loneSurrogateProbe = /[\ud800-\udfff]/;

function escapeLoneSurrogates(text) {
  var s = String(text);
  if (!loneSurrogateProbe.test(s)) return s;
  var out = '';
  for (var i = 0; i < s.length; i++) {
    var code = s.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < s.length) {
      var next = s.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        out += s.charAt(i) + s.charAt(i + 1);
        i++;
        continue;
      }
    }
    if (code >= 0xD800 && code <= 0xDFFF) out += '\\u' + code.toString(16);
    else out += s.charAt(i);
  }
  return out;
}
