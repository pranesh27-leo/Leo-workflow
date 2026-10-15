# Manifest

<!-- One row per hunk in `git diff`. Every row needs all three of Task, Why
     and If deleted.

     Never invent a task ID to make a hunk look justified. A hunk serving no
     task gets `-`, and an honest `-` is the entire value of this table: it
     says "this went in unrequested", which is a thing the developer needs to
     know and cannot see in a diff. -->

| # | Hunk | Delta | Task | Why | If deleted |
|---|------|-------|------|-----|------------|
| 1 | `<file>:<line>` | +<n>/-<n> | <T1 or -> | <why this hunk exists> | <what breaks> |

Budget: est <n> LOC / actual <n> LOC
Tests: `<command>` -- <paste the real output, not a claim>
