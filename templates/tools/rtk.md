# RTK — terminal output reduction

Structural filtering: progress bars, repeated lines, package-manager noise. It
stays on in every mode precisely because it is structural — it is not a model
deciding which lines you needed to see.

## Exclude leo from the rewrite — this one matters

RTK's hook rewrites the agent's Bash calls, and the agent runs `leo check`
through Bash. A compressed check is a check whose failures you may not see —
and `leo check` writes the test result it just observed into the manifest, so a
truncated run becomes a recorded claim about tests that nobody actually read.
That claim then lands in the commit message.

```toml
# ~/.config/rtk/config.toml
# macOS: ~/Library/Application Support/rtk/config.toml
[hooks]
exclude_commands = ["leo"]
```

## `rtk tree` needs tree(1)

`rtk tree` wraps the native `tree` binary rather than implementing it. Without
it you get `tree command not found`, which reads like an rtk failure and is
not. Install `tree` separately, or use `rtk ls` instead.

Every other subcommand — `ls`, `find`, `read`, `grep`, `rg`, `git`, `json`,
`docker`, `diff` — is self-contained.
