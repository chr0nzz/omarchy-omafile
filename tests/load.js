'use strict';

var fs = require('node:fs');
var path = require('node:path');
var vm = require('node:vm');

function loadModule(relativeName) {
  var filePath = path.join(__dirname, '..', relativeName);
  var code = fs.readFileSync(filePath, 'utf8');
  var sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: filePath });
  return sandbox;
}

module.exports = loadModule;
