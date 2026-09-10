# MUST NOT ship a command that the docs do not mention

MUST: every file in `core/cmd/` appears in `leo help` and in GUIDE.md's command
reference. Dropping a file into `core/cmd/` is all it takes to add a command,
which is the point — and also why one can quietly exist that nobody has ever
been told about.

Learned from: `GUIDE.md` and `.leo/workflow.md` were written to overlap almost
entirely, so a change to one silently made the other wrong. The prose split is
now by role; this catches the one part of it a shell command can see.

Learned again, from the rule failing open: the GUIDE test was `grep "leo $c"`,
and the sentence "leo uses the MCP names..." made `leo use` look documented the
moment the command existed. A check whose match is that loose is worse than no
check, because it reports success. It is anchored on the backtick now.

## Verify

```sh
missing=""
for f in core/cmd/*.sh; do
  c=$(basename "$f" .sh)
  ./leo help 2>&1 | grep -q "^  $c" || missing="$missing help:$c"
  # Backtick-anchored, not bare prose. `grep "leo use"` matched the sentence
  # "leo uses the MCP names..." in an unrelated paragraph, so this rule
  # reported `leo use` as documented on the day it was added and undocumented
  # nowhere. A command reference in GUIDE.md is always in backticks.
  grep -q '`leo '"$c" GUIDE.md   || missing="$missing guide:$c"
done
[ -z "$missing" ] && exit 0
echo "undocumented:$missing"
exit 1
```
