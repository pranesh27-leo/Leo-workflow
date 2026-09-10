# MUST NOT ship a skill the agent's runtime cannot see

MUST: every skill under `templates/skills/<name>/SKILL.md` is installed by
`leo init` into a path the agent actually reads, not only into `.leo/skills/`.

`.leo/skills/` is the canonical copy — vendored, unmodified, and the thing a
team amends. It is not a path any agent runtime loads. Claude Code reads
`.claude/skills/`, so that is where `init` puts the working copy, and the two
must stay in step.

Learned from shipping exactly this bug. leo vendored the grill into
`.leo/skills/grilling/SKILL.md`, `templates/skills/README.md` told the
developer to symlink it into `.claude/skills/` by hand, and that step appeared
in no stage of the loop. The result: `leo check` failed an ungrilled task and
pointed at a skill file that was never registered anywhere, in a repository
where `/grill-me` did not exist. Everything passed. The skill did nothing.

This is `COMMANDS-DOCUMENTED` for skills: that rule catches a command no
document mentions, this one catches a skill no runtime loads.

## Verify

```sh
missing=""
for d in templates/skills/*/; do
  [ -f "$d/SKILL.md" ] || continue
  n=$(basename "$d")
  # init must install it somewhere a runtime reads, not just under .leo/.
  grep -q "\.claude/skills/\$_s/SKILL.md\|\.claude/skills/$n/SKILL.md" \
    core/cmd/init.sh || missing="$missing $n"
done

# And the loop must name the directory, so nobody re-adds the manual step.
grep -q '\.claude/skills' core/cmd/init.sh || missing="$missing init-installs-nothing"

[ -z "$missing" ] && exit 0
echo "skills the runtime cannot see:$missing"
echo "  .leo/skills/ is the canonical copy; no agent reads it."
exit 1
```
