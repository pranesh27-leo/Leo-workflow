# MUST NOT let a stage exist that the workflow does not name

MUST: every stage of the loop is named in `templates/workflow.md`, and every
command that stage depends on exists in `core/cmd/`.

The loop is `grill me -> plan -> task creation -> build -> manifest -> commit`,
and the agent is expected to know all six even when the developer names none of
them. That only works if the file the agent reads actually lists them.

Learned from: `leo task` was added as a stage between plan and build. Nothing
in leo would have failed if `templates/workflow.md` had never mentioned it —
the command works, the tests pass, and the agent simply never runs it, because
the file it reads to find out what to do next does not say the stage exists.
This is `COMMANDS-DOCUMENTED` one level up: that rule catches a command no
document mentions, this one catches a *stage* no document mentions.

## Verify

```sh
w=templates/workflow.md
missing=""
[ -f "$w" ] || { echo "no $w"; exit 1; }

# The six stage names, as the loop header spells them.
for stage in "grill" "plan" "task" "build" "manifest" "commit"; do
  grep -qi "$stage" "$w" || missing="$missing stage:$stage"
done

# And the commands those stages run. A stage naming a command that does not
# exist is the same failure from the other side.
for c in plan task scan check commit; do
  [ -f "core/cmd/$c.sh" ] || missing="$missing cmd:$c"
  grep -q "leo $c" "$w"   || missing="$missing workflow:$c"
done

[ -z "$missing" ] && exit 0
echo "flow undocumented:$missing"
exit 1
```
