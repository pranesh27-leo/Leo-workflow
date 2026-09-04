#!/usr/bin/env bash
# Headroom — context compression. Apache-2.0, github.com/headroomlabs-ai/headroom
#
# Semantic compression at the API boundary, which is why every mode that exists
# to preserve detail turns it off. During debugging the line that matters is
# routinely the line that looks like noise.

headroom_present() { command -v headroom >/dev/null 2>&1; }

headroom_hint() {
  say "uv tool install --python 3.13 \"headroom-ai[all]\""
  say "note: pulls ONNX Runtime and downloads a model on first use"
}

# The RTK overlap is a conflict between two declared capabilities, and
# `leo session` reports it whether or not either is installed. What belongs
# here is the part that is only true once headroom is on the machine.
headroom_advice() {
  if [ "$(cap_state serena)" = "on" ]; then
    say "\`headroom wrap claude\` installs Serena itself, at user scope in ~/.claude.json,"
    say "  and leaves it there until unwrapped. Do not configure Serena twice."
  fi
}

# Heavier than the rest: a Python toolchain, ONNX Runtime, and a model
# downloaded on first use. Worth saying before someone types y.
headroom_install() {
  say "uv tool install --python 3.13 'headroom-ai[all]'"
}
