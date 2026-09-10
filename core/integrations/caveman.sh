#!/usr/bin/env bash
# Caveman — agent prose reduction. github.com/JuliusBrussee/caveman
#
# Off in every mode by default, including coding. A tool that changes how the
# agent talks to you should be asked for, not arrive with a mode.
#
# Licensing is split and worth knowing before you install: the skill, SDK and
# CLI are MIT; the engine, proxy and rewriter are BSL-1.1 until 2030. Telemetry
# is on by default -- `caveman telemetry off` if that matters to you.

# What `caveman_install` actually puts on disk, verified by running it: `npx
# skills add` writes into the REPOSITORY, at .agents/skills/caveman* with
# .claude/skills/ symlinks beside it. `command -v caveman` could never have
# found that, so the capability reported MISSING forever after a successful
# install and `leo install` told everyone to open a new shell.
#
# The guard is not decoration: a function ending in a bare test against a
# missing path can exit 2, which is leo's code for "no adapter" -- the ponytail
# bug, recorded in .leo/rules/ADAPTER-CONTRACT.md.
#
# command -v stays as a third signal, for anyone who installed the BSL-1.1 CLI
# half deliberately. leo still will not install it for them.
caveman_present() {
  [ -d "${ROOT:-.}/.agents/skills/caveman" ] && return 0
  [ -d "${ROOT:-.}/.claude/skills/caveman" ] && return 0
  command -v caveman >/dev/null 2>&1
}

caveman_hint() {
  say "skill only (MIT, no daemon):  npx skills add JuliusBrussee/caveman"
  say "not an npm package: \`npx caveman\` fails to resolve an executable"
  say "the gateway half is BSL-1.1 and leo does not use it -- see the doc"
}

caveman_advice() {
  say "skill only — the exemption list is in the doc above, and it is not optional"
}

# The MIT skill only. The proxy is the BSL-1.1 half, it runs a daemon, and it
# adds input tokens of its own -- leo will not install that for you.
caveman_install() {
  say "npx --yes skills add JuliusBrussee/caveman"
}

# Ambient: this wraps the session rather than being called at a moment, so
# `_present` is the evidence and the agent is never asked to announce it.
caveman_kind() { printf 'ambient'; }
