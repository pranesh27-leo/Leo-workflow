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
ponytail_present() {
  [ -f "${ROOT:-.}/AGENTS.md" ] || return 1
  grep -qi 'ponytail' "$ROOT/AGENTS.md" 2>/dev/null
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
