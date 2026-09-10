function toSet(arr) {
  var o = {};
  for (var i = 0; i < arr.length; i++) o[arr[i]] = true;
  return o;
}

var imageExtSet = toSet(['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif', 'heic', 'avif']);
var videoExtSet = toSet(['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', 'mpg', 'mpeg']);
var audioExtSet = toSet(['mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'wma', 'opus']);
var archiveExtSet = toSet(['zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'zst', 'tgz']);
var codeExtSet = toSet(['js', 'jsx', 'ts', 'tsx', 'py', 'rb', 'go', 'rs', 'c', 'h', 'cpp', 'hpp', 'java', 'kt', 'swift', 'sh', 'json', 'yaml', 'yml', 'toml', 'xml', 'html', 'css', 'scss', 'sql', 'lua', 'vim']);
var documentExtSet = toSet(['doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'xls', 'xlsx', 'csv', 'ppt', 'pptx']);
var fontExtSet = toSet(['ttf', 'otf', 'woff', 'woff2']);

var categoryGlyphs = {
  folder: '',
  image: '',
  video: '',
  audio: '',
  archive: '',
  code: '',
  document: '',
  pdf: '',
  font: '',
  executable: '',
  link: '',
  broken: '',
  file: ''
};

var extensionGlyphs = {
  html: '',
  css: '',
  scss: '',
  doc: '',
  docx: '',
  xls: '',
  xlsx: '',
  csv: '',
  ppt: '',
  pptx: ''
};

var placeGlyphs = {
  home: '',
  desktop: '',
  documents: '',
  downloads: '',
  music: '',
  pictures: '',
  videos: '',
  templates: '',
  publicshare: '',
  trash: '',
  root: '',
  drive: '',
  usb: '',
  network: '',
  pinned: '',
  recent: '',
  search: ''
};

var actionGlyphs = {
  copy: '',
  cut: '',
  paste: '',
  rename: '',
  trash: '',
  'delete': '',
  newfolder: '',
  newfile: '',
  up: '',
  back: '',
  forward: '',
  refresh: '',
  search: '',
  hidden: '',
  list: '',
  grid: '',
  columns: '',
  split: '',
  close: '',
  add: '',
  sort: '',
  menu: '',
  eject: '',
  open: '',
  terminal: '',
  editor: '',
  properties: '',
  cancel: '',
  check: '',
  warning: '',
  error: '',
  chevronRight: '',
  chevronDown: '',
  chevronUp: '',
  chevronLeft: ''
};

var FALLBACK_CATEGORY = '';
var FALLBACK_PLACE = '';
var FALLBACK_ACTION = '';

function localCategory(entry) {
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

function glyphForCategory(category) {
  return categoryGlyphs[category] || FALLBACK_CATEGORY;
}

function glyphFor(entry) {
  if (!entry) return FALLBACK_CATEGORY;
  var category = localCategory(entry);
  var ext = String(entry.ext || '').toLowerCase();
  if (extensionGlyphs[ext]) return extensionGlyphs[ext];
  return glyphForCategory(category);
}

function placeGlyph(key) {
  var k = String(key || '').toLowerCase();
  return placeGlyphs[k] || FALLBACK_PLACE;
}

function actionGlyph(name) {
  var n = String(name || '');
  return actionGlyphs[n] || FALLBACK_ACTION;
}
