#!/usr/bin/env bash
# Ponytail — generated-code minimisation. MIT, github.com/DietrichGebert/ponytail
#
# A ruleset, not a program: check whether the thing needs to exist, whether it
# already exists, whether the standard library does it, before writing code.
#
# It overlaps with leo more than with anything else on this list. leo's budget
# check and the manifest's "If deleted" column already push toward the same
# thing -- the difference is that leo verifies and Ponytail advises. Both is
# fine; if you had to pick one, keep the one with teeth.

# Detected by its ruleset being in AGENTS.md, which is the form that works with
# every agent. The plugin installs cannot be detected portably, so a developer
# using the plugin should add the ruleset too, or read this as a false negative.
#
# leo's own generated block is cut out before the grep, and that is not a
# nicety. `leo agents --auto` writes a row naming every capability, ponytail
# included, into exactly the file this function reads. Without the exclusion
# the tool detected itself the moment leo described it: "installed" for every
# repository that had run `leo agents`, on a machine where nobody had ever
# installed anything. It also made the fingerprint unstable -- writing the
# block changed the answer the block was a fingerprint of -- so `leo agents
# --check` failed immediately after `--auto` succeeded.
ponytail_present() {
  [ -f "${ROOT:-.}/AGENTS.md" ] || return 1
  awk '
    /leo:tools begin/ { skip = 1 }
    !skip { print }
    /leo:tools end/   { skip = 0 }' "$ROOT/AGENTS.md" 2>/dev/null \
    | grep -qi 'ponytail'
}

ponytail_hint() {
  say "the ruleset:  https://github.com/DietrichGebert/ponytail  -> append AGENTS.md"
  say "Claude Code:  /plugin marketplace add DietrichGebert/ponytail"
  say "              /plugin install ponytail@ponytail"
}

ponytail_advice() {
  say "the plan outranks it: a task that asks for an abstraction gets the abstraction"
  say "an honest '-' row in the manifest is still the stronger check"
}

# The ruleset form, appended to AGENTS.md -- the one that works with every
# agent rather than only the ones with a plugin system. It is about 2.5KB, and
# AGENTS.md loads on every request, so this is a real cost and not a free one.
ponytail_install() {
  say "printf '\\n' >> AGENTS.md"
  say "curl -fsSL https://raw.githubusercontent.com/DietrichGebert/ponytail/main/AGENTS.md >> AGENTS.md"
}

# Ambient: this wraps the session rather than being called at a moment, so
# `_present` is the evidence and the agent is never asked to announce it.
ponytail_kind() { printf 'ambient'; }

ponytail_oneline() {
  printf 'Ambient. Nothing to announce, and nothing you can call at a moment.'
}

ponytail_label() { printf 'Ponytail'; }
