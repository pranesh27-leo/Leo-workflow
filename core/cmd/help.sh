#!/usr/bin/env bash
# desc: show this help
# usage: leo help

cat >&2 <<EOF

leo $(leo_version) — keep AI-written code reviewable.

CYCLE ONE — build it
  You    grill the agent, then    leo plan "rate limiting"
  Agent  leo task T1              each task gets a file and a to-do
  Agent  builds it one task at a time, updating Status as it goes
  Agent  leo scan                 500 lines -> ~20 rows, one per hunk
  Agent  leo use serena           announces the tool, and logs that it did
  Agent  leo check                rules, scope, tools, budget, tests -- STOPS
  Agent  leo record "api: ..."    the cycle's message, filed, not committed
  ...    repeat for the next cycle -- nothing is in git yet
  You    leo commit               one commit, every recorded cycle in it

CYCLE TWO — read it, in a new session
  You    leo session --mode review
  Agent  leo review <sha>         briefed from the commit cycle one wrote
  Agent  reads the diff against .leo/review/STANDARDS.md, files findings
  You    leo review --close       no open blocker, a real verdict, signed

  Cycle two cannot edit the code. A finding becomes a new cycle one, or a
  waiver -- and both of those are yours.

COMMANDS
  init [--force]          set up this repository
  session [--mode <name>] declare what kind of work this is -- coding,
                          debugging, learning, review, exploration. Optional,
                          and it switches nothing on: it says what this work
                          wants, tells you what is missing, and lands in the
                          commit message.
  session --report        where this change stands: plan, mode, size,
                          manifest, tests, approval
  install [<name>|--all]  install a tool this session declares. Shows the
                          command first. Refuses without a human at a terminal.
                          Nothing else in leo installs anything.
  plan ["<name>"]         start a change, or show it and where it stands
  task [T1] [--force]     give a plan task its own file and to-do, or list
                          them all with their progress. The file carries the
                          grill for that task; \`leo check\` fails while it is
                          still marked ungrilled.
  task T1 --sub "<name>"  add a subtask as a heading inside T1.md. Subtasks
                          never get files of their own, and each arrives
                          ungrilled -- it is grilled before it is built,
                          exactly as its parent was.
  use <name>              say which tool you are about to use. Prints it for
                          the developer and logs it to .leo/used, in one
                          action, so what they see is what \`leo check\` reads.
                          Refuses a tool the session has switched off, and
                          records that it was asked for.
  use --list              the tools used this cycle
  scan [base]             enumerate hunks into .leo/manifest.md
  check [--verbose]       rules + unreviewed hunks + invented task IDs
                          + grill + tools + TDD + budget + tests. A tool the
                          session declares ON must have left evidence it was
                          used; one that is OFF must have left none. Quiet when it passes,
                          loud when it does not -- every line a passing check
                          prints is re-read on every later turn. --verbose
                          shows each stage.
  record "<subject>"      end the cycle without ending the change: check it,
                          file the commit message this cycle would have made
                          into .leo/commits/, clear the manifest, stop. Nothing
                          reaches git, so an agent may run this.
  commit ["<subject>"]    land it. Every recorded cycle becomes a section of
                          one commit message, in order. With nothing recorded
                          it commits the manifest directly, as it always did.
                          Refuses without a human at a terminal.
  commit --list           the cycles recorded and still not in git
  review [<rev>]          open cycle two: a review of a commit that has
                          already landed, briefed from the dev cycle that
                          made it -- goal, manifest, non-goals and the
                          decisions the grill settled. Default HEAD; a range
                          <a>..<b> is reviewed as one. Shows the review if
                          one is already open.
  review --close          the gate of cycle two. Every finding dispositioned,
                          the severity and status vocabulary readable, no
                          blocker left open, and a verdict somebody actually
                          typed. Stamps the review closed.
  review --list           every review in the repository, and its state
  build [--out <path>]    compile the source tree into one self-contained
                          file (default dist/leo). Vendor that into the repo
                          you work in, so it depends on a file it contains
                          rather than on a clone somewhere else.
  help                    this

FILES
  AGENTS.md               agent instructions, loaded every session (keep it short)
  .leo/workflow.md        the loop, read on demand
  .leo/rules/*.md         one lesson per file, each with a shell check
  core/integrations/*.sh  the tools leo ships with: detect, hint, install, advise
  .leo/integrations/*.sh  the tools your repo adds. Same contract, no registry.
  .leo/config             TEST_CMD
  .leo/session            current mode (gitignored — it lands in the commit)
  .leo/plan.md            current change (gitignored — it lands in the commit)
  .leo/tasks/*.md         one per task: "Done when", a to-do, notes (same)
  .leo/manifest.md        current scope table (same)
  .leo/used               which declared tools built this cycle's hunks (same)
  .claude/skills/*/       the vendored skills, installed where Claude Code
                          actually reads them. TRACKED: a skill that only
                          works for whoever last ran \`leo init\` is no skill.
  .leo/commits/*.md       one per cycle recorded but not yet landed. Gitignored
                          for the same reason as the rest: each one ends up
                          inside the commit message it describes.
  .leo/review/STANDARDS.md what cycle two argues against — yours to amend
  .leo/reviews/*.md       one review per commit. TRACKED, not gitignored:
                          the plan and the manifest end up inside the commit
                          message they describe, and a review of a commit
                          that already exists has nowhere else to live.

AFTER A DISCONNECT
  Nothing lives in the chat, so a dropped session costs nothing:
    leo session --report  the whole change on one screen, and what is next
    leo plan              the plan, plus "2 of 5 done | in progress: T3"
    leo task              every task and how far its to-do got
    git diff HEAD         the code, still there
    cat .leo/manifest.md  the review table, as far as it got
    leo commit --list     the cycles already recorded, still waiting to land

WHY
  The diff shows what changed. The manifest shows why each hunk exists and what
  breaks without it. It ends up in the commit message, so when production breaks
  at 3am you run \`git blame\` and get an answer without asking an AI anything.

EOF
