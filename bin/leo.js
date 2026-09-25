#!/usr/bin/env node
'use strict';
// leo — keep AI-written code reviewable.
//
// The entry point npm installs, and the whole of it: leo is a Node program
// now, so there is no bash to find and nothing to hand over to.
//
// This file stays three lines because everything that can fail lives in src/,
// where a test can require it without starting a process.
require('../src/cli').main(process.argv.slice(2));
