'use strict';
// Caveman — prose compression, as a skill. MIT half only.
const path = require('path');
const { isDir } = require('../lib/fsx');
const { onPath } = require('./_which');

exports.label = () => 'Caveman';

exports.present = (ctx) => {
  const root = ctx.root || '.';
  if (isDir(path.join(root, '.agents', 'skills', 'caveman'))) return true;
  if (isDir(path.join(root, '.claude', 'skills', 'caveman'))) return true;
  return onPath('caveman');
};

exports.hint = () => [
  'skill only (MIT, no daemon):  npx skills add JuliusBrussee/caveman',
  'not an npm package: `npx caveman` fails to resolve an executable',
  'the gateway half is BSL-1.1 and leo does not use it -- see the doc',
];

exports.advice = () => [
  'skill only — the exemption list is in the doc above, and it is not optional',
];

exports.install = () => ['npx --yes skills add JuliusBrussee/caveman'];
exports.kind = () => 'ambient';
exports.oneline = () => 'Compresses prose. Never compress code, output, or anything the developer asked to read line by line.';
