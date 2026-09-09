#!/usr/bin/env bash
# TDD — write the test first, and watch it fail before you make it pass.
#
# Not a tool. Every other adapter here names something the developer installs;
# this one names a practice, and it is in this directory because the adapter
# contract is already the machinery for "the developer turns this on and off
# per mode" and a second mechanism for the same job would be worse than this
# slight stretch of the word "capability".
#
# What it toggles is the ORDER, and only the order. `leo check` runs TEST_CMD
# and records the result in the manifest whether this is on or off, and no mode
# can change that -- it is an engineering control and lives in check.sh. With
# TDD off you may write the test afterwards; you may not skip it.

# Installed means: this repository can actually run its tests. Without a
# TEST_CMD there is nothing to watch fail, and a capability that reported
# itself available would be lying about the one thing it needs.
#
# The guard is not decoration. A function whose last command is a bare test
# against something missing can exit 2, which is leo's code for "no adapter"
# -- the ponytail bug, recorded in .leo/rules/ADAPTER-CONTRACT.md.
tdd_present() {
  [ -n "${TEST_CMD:-}" ] || return 1
  return 0
}

tdd_label() { printf 'TDD'; }

tdd_hint() {
  say "set TEST_CMD in .leo/config — that is the whole install"
  say "  TEST_CMD=\"go test ./...\"   TEST_CMD=\"npm test\"   TEST_CMD=\"pytest -q\""
}

# No tdd_install. leo cannot know this repository's test command, and writing a
# guess into .leo/config would be leo committing config nobody approved.
# `leo install` reports it as "manual" and prints the hint, which is correct.

tdd_advice() {
  say "red before green: the test fails first, for the reason you expect"
  say "leo task seeds the to-do with those steps while this is on"
}
