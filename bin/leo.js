#!/usr/bin/env node
'use strict';
// leo — keep AI-written code reviewable.
//
// The entry point npm installs. It is deliberately three lines: everything
// that can fail lives in src/, where it can be required from a test without
// running a process.
require('../src/cli').main(process.argv.slice(2));
