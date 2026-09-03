#!/usr/bin/env bash
# desc: show this help
# usage: leo help

cat >&2 <<EOF

leo $(cat "$LEO_HOME/VERSION") — keep AI-written code reviewable.

  Ask for the change      leo plan "rate limiting"    write down what it may be
  Let the agent build it  (your normal AI session)
  Break the diff up       leo scan                    500 lines -> ~20 rows
  Prove it                leo check                   rules, scope, budget, tests
  Record why              leo commit "api: rate limit" manifest -> commit message

COMMANDS
  init [--force]          set up this repository
  plan ["<name>"]         show the plan, or start one
  scan [base]             enumerate hunks into .leo/manifest.md
  check [base]            rules + unmapped hunks + budget + tests
  commit "<subject>"      commit with the manifest in the message
  help                    this

FILES
  AGENTS.md               agent instructions, loaded every session (keep it short)
  .leo/workflow.md        the loop, read on demand
  .leo/rules/*.md         one lesson per file, each with a shell check
  .leo/config             TEST_CMD
  .leo/plan.md            current change (gitignored — it lands in the commit)
  .leo/manifest.md        current review table (same)

WHY
  The diff shows what changed. The manifest shows why each hunk exists and what
  breaks without it. It ends up in the commit message, so when production breaks
  at 3am you run \`git blame\` and get an answer without asking an AI anything.

EOF
