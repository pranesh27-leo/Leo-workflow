#!/usr/bin/env bash
# Caveman — agent prose reduction. github.com/JuliusBrussee/caveman
#
# Off in every mode by default, including coding. A tool that changes how the
# agent talks to you should be asked for, not arrive with a mode.
#
# Licensing is split and worth knowing before you install: the skill, SDK and
# CLI are MIT; the engine, proxy and rewriter are BSL-1.1 until 2030. Telemetry
# is on by default -- `caveman telemetry off` if that matters to you.

caveman_present() { command -v caveman >/dev/null 2>&1; }

caveman_hint() {
  say "skill only (MIT, no daemon):  npx skills add JuliusBrussee/caveman"
  say "the proxy is BSL-1.1 and adds ~1-1.5k input tokens per turn -- skip it"
}

caveman_advice() {
  say "brevity never applies to the manifest: Why and If deleted are the record"
  say "or to a rule violation, a failing test, or an error message"
}

# The MIT skill only. The proxy is the BSL-1.1 half, it runs a daemon, and it
# adds input tokens of its own -- leo will not install that for you.
caveman_install() {
  say "npx --yes skills add JuliusBrussee/caveman"
}
