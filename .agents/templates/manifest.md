# Manifest

<!-- One row per hunk in `git diff`. Every row needs all four of Task, Why,
     Source and If deleted.

     Never invent a task ID to make a hunk look justified. A hunk serving no
     task gets `-`, and an honest `-` is the entire value of this table: it
     says "this went in unrequested", which is a thing the developer needs to
     know and cannot see in a diff.

     Source is where the hunk's shape came from, one of three:
       grill               the developer decided it (the goal's ## Grill)
       pattern path:LINE   the repository already does it this way, there
       default             your own choice. Nobody asked, no code showed it.
     `default` is the row the developer reads closely. Write it honestly. -->

| # | Hunk | Delta | Task | Why | Source | If deleted |
|---|------|-------|------|-----|--------|------------|
| 1 | `<file>:<line>` | +<n>/-<n> | <T1 or -> | <why this hunk exists> | <grill / pattern `path:LINE` / default> | <what breaks> |

Budget: est <n> LOC / actual <n> LOC
Tests: `<command>` -- <paste the real output, not a claim>
