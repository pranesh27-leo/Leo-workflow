'use strict';
// Headroom — semantic context compression.
const { onPath } = require('./_which');

exports.label = () => 'Headroom';
exports.present = () => onPath('headroom');

exports.hint = () => [
  'uv tool install --python 3.13 "headroom-ai[all]"',
  'note: pulls ONNX Runtime and downloads a model on first use',
];

// The Serena line is conditional because it is only true when Serena is on:
// headroom installs its own copy, user-scope, and saying so unconditionally
// would be advice about a tool this session is not using.
exports.advice = (ctx, api) => {
  if (api && api.capState('serena') === 'on') {
    return ['`headroom wrap claude` installs Serena itself, user-scope — see the doc above'];
  }
  return [];
};

exports.install = () => ["uv tool install --python 3.13 'headroom-ai[all]'"];
exports.kind = () => 'ambient';
exports.oneline = () => 'Compresses the context semantically. Ambient — and it fights RTK: see leo session for why.';
