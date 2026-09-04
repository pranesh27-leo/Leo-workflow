#!/usr/bin/env bash
# RTK — terminal output reduction. Apache-2.0, github.com/rtk-ai/rtk
#
# Structural filtering: progress bars, repeated lines, package-manager noise.
# It stays on in every mode precisely because it is structural -- it is not a
# model deciding which lines you needed to see.

rtk_present() { command -v rtk >/dev/null 2>&1; }

rtk_hint() {
  say "brew install rtk        (or: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh)"
  say "rtk init -g             installs the auto-rewrite hook"
}

# The one thing leo has to say about RTK. Its hook rewrites the agent's Bash
# calls, and the agent runs `leo check` through Bash. A compressed check is a
# check whose failures the agent may not see -- and `leo check` writes the test
# result it just observed into the manifest, so a truncated run becomes a
# recorded claim about tests that nobody actually read.
rtk_advice() {
  say "exclude leo from the rewrite, in ~/.config/rtk/config.toml"
  say "  [hooks]"
  say "  exclude_commands = [\"leo\"]"
  say "on macOS: ~/Library/Application Support/rtk/config.toml"
}
