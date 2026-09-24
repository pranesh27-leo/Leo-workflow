'use strict';
// RTK — structural output filtering. Wraps the shell, not the model.
const { onPath } = require('./_which');

exports.label = () => 'RTK';
exports.present = () => onPath('rtk');

exports.hint = () => [
  'brew install rtk        (or: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh)',
  'rtk init -g             installs the auto-rewrite hook',
];

exports.advice = () => [
  'exclude leo from the hook rewrite — the config block is in the doc above',
];

exports.install = () => {
  const out = onPath('brew')
    ? ['brew install rtk']
    : ['curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh'];
  out.push('rtk init -g');
  return out;
};

exports.kind = () => 'ambient';
exports.oneline = () => 'Wraps shell output and filters it structurally. Nothing to announce; it is already in effect.';
