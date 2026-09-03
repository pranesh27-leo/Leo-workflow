#!/usr/bin/env bash
# desc: show this help
# usage: leo help

cat >&2 <<EOF

leo $(cat "$LEO_HOME/VERSION") — keep AI-written code reviewable.

  You    grill the agent, then    leo plan "rate limiting"
  Agent  builds it one task at a time, updating Status as it goes
  Agent  leo scan                 500 lines -> ~20 rows, one per hunk
  Agent  leo check                rules, scope, budget, tests -- then STOPS
  You    leo commit "api: ..."    you decide the change is done, not it

COMMANDS
  init [--force]          set up this repository
  plan ["<name>"]         start a change, or show it and where it stands
  scan [base]             enumerate hunks into .leo/manifest.md
  check                   rules + unreviewed hunks + invented task IDs
                          + budget + tests
  commit "<subject>"      commit with the manifest in the message.
                          Refuses without a human at a terminal.
  help                    this

FILES
  AGENTS.md               agent instructions, loaded every session (keep it short)
  .leo/workflow.md        the loop, read on demand
  .leo/rules/*.md         one lesson per file, each with a shell check
  .leo/config             TEST_CMD
  .leo/plan.md            current change (gitignored — it lands in the commit)
  .leo/manifest.md        current review table (same)

AFTER A DISCONNECT
  Nothing lives in the chat, so a dropped session costs nothing:
    leo plan              the plan, plus "2 of 5 done | in progress: T3"
    git diff HEAD         the code, still there
    cat .leo/manifest.md  the review table, as far as it got

WHY
  The diff shows what changed. The manifest shows why each hunk exists and what
  breaks without it. It ends up in the commit message, so when production breaks
  at 3am you run \`git blame\` and get an answer without asking an AI anything.

EOF
