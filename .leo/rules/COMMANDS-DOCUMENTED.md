# MUST NOT ship a command that the docs do not mention

MUST: every file in `core/cmd/` appears in `leo help` and in GUIDE.md's command
reference. Dropping a file into `core/cmd/` is all it takes to add a command,
which is the point — and also why one can quietly exist that nobody has ever
been told about.

Learned from: `GUIDE.md` and `.leo/workflow.md` were written to overlap almost
entirely, so a change to one silently made the other wrong. The prose split is
now by role; this catches the one part of it a shell command can see.

## Verify

```sh
missing=""
for f in core/cmd/*.sh; do
  c=$(basename "$f" .sh)
  ./leo help 2>&1 | grep -q "^  $c" || missing="$missing help:$c"
  grep -q "leo $c" GUIDE.md      || missing="$missing guide:$c"
done
[ -z "$missing" ] && exit 0
echo "undocumented:$missing"
exit 1
```
