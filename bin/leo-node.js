#!/usr/bin/env node
'use strict';
// The Node port's entry point, while the port is in flight.
//
// NOT bin/leo.js. That one is the shipped npm entry and still finds a bash to
// run the shell implementation with -- overwriting it would make every
// installed `leo` run a port that does not have scan, check, record, commit,
// review, docs or build yet. The two swap over in the final phase, when the
// Node side passes the suite that the shell side passes now.
require('../src/cli').main(process.argv.slice(2));
