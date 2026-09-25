#!/usr/bin/env node
'use strict';
// leo — keep AI-written code reviewable.
//
// Running leo straight out of a clone. bin/leo.js is the same three lines for
// the npm install; both exist because `npm install -g` needs its entry under
// bin/ and a developer with a clone expects ./leo to work.
require('./src/cli').main(process.argv.slice(2));
