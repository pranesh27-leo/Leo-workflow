'use strict';
// "Is this program installed?" — the `command -v` every adapter used.
//
// PATH is walked directly rather than shelling out to `where`/`which`: one
// less subprocess on a path that runs seven times per leo command, and no
// dependence on a lookup tool being present. PATHEXT is honoured on Windows,
// where `rtk` on disk is `rtk.cmd` or `rtk.exe` and a bare name never matches.
const fs = require('fs');
const path = require('path');

function onPath(name) {
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const exts = process.platform === 'win32'
    ? (process.env.PATHEXT || '.COM;.EXE;.BAT;.CMD').split(';').filter(Boolean)
    : [''];
  for (const d of dirs) {
    for (const ext of exts) {
      const p = path.join(d, name + ext);
      try {
        const st = fs.statSync(p);
        if (st.isFile()) return true;
      } catch (e) { /* next */ }
    }
  }
  return false;
}

module.exports = { onPath };
