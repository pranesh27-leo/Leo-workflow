# Adapters — teaching leo about a tool it does not ship with

Drop a `<name>.sh` in this directory. leo sources every `*.sh` here on every
command and the file name becomes the capability name, so `vitals.sh` gives you
`leo session --vitals on` and `leo install vitals`. There is no registry.

**Define functions and nothing else.** leo sources this file into its own shell
on every single command. A file that runs work at source time runs it on every
`leo check`. A file that calls `exit` takes leo down with it. leo parses each
adapter before sourcing it and skips one that does not compile, but it cannot
protect you from a file that parses and then misbehaves.

Two functions are required, four are optional:

```sh
#!/usr/bin/env bash
# vitals — codebase hotspots, ranked by ROI. MIT, github.com/chopratejas/vitals

# REQUIRED. Exit 0 if the tool is installed.
vitals_present() { command -v vitals >/dev/null 2>&1; }

# REQUIRED. How to install it by hand. Use `say`, one line per line.
vitals_hint()    { say "npx --yes skills add chopratejas/vitals"; }

# Optional. What `leo install vitals` runs. It PRINTS the command; leo shows it
# to the developer, asks, and only then runs it. Without this, leo reports the
# capability as "manual" and prints your hint instead.
vitals_install() { say "npx --yes skills add chopratejas/vitals"; }

# Optional. On or off by default, per session mode. Without this, off in every
# mode -- which is the right default for something leo knows nothing about.
vitals_default() { case "$1" in review|debugging) printf 'on' ;; *) printf 'off' ;; esac; }

# Optional. What the agent should do with it when it is on. $MODE is readable.
vitals_advice()  { say "rank hotspots by ROI before picking what to fix"; }

# Optional. Display name. Without this, leo shows the file name.
vitals_label()   { printf 'Vitals'; }
```

That is the whole contract. An adapter never installs, launches or configures
anything by itself — `leo install` is the only command that changes your
machine, and it asks first.

This directory is committed, so a capability your team depends on arrives with
the repository rather than in somebody's setup notes.
