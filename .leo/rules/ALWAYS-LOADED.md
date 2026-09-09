# MUST NOT grow what loads on every request

MUST: the always-loaded context stays small, and nothing read-on-demand
becomes always-loaded by accident.

`AGENTS.md` and `CLAUDE.md` are read on **every request of every session**.
`.leo/workflow.md`, `CONTEXT.md` and `.leo/tools/*.md` are read on demand. The
difference between those two categories is the difference between paying once
and paying forever.

Learned from measurement, not taste. Reading real session transcripts
(`t/bench-session.sh --all`, results in `.leo/plans/C5-benchmark/RESULTS.md`)
showed leo sessions spending **1.76x more cached tokens per turn** than
sessions without it, while spending 1.71x *fewer* fresh ones. Cache re-reads
are ~95% of all token volume, so the always-loaded files — re-read every turn,
forever — are leo's real cost, and the manifest savings do not cover them.
leo came out ~17% more expensive per turn overall.

The failure this prevents is one line: adding `@.leo/workflow.md` to
`AGENTS.md`. It looks like a helpful convenience, it makes the agent more
reliable in the short run, and it silently multiplies 10KB by every request
anyone ever makes.

Three things are checked, and they are the three levers:

1. **A byte budget** on the always-loaded pair. Bytes, not lines — a line cap
   is defeated by long lines, and the model pays for bytes.
2. **No imports** from `AGENTS.md`. An import makes a read-on-demand file
   always-loaded, which is the whole distinction collapsing.
3. **Tool docs are pointed at, never printed.** `leo session` prints a path;
   whoever needs the content opens it. Printing it would put seven files into
   context for a session that needed none of them.

## Verify

```sh
budget=2400
missing=""

a=templates/AGENTS.md
c=templates/CLAUDE.md
for f in "$a" "$c"; do
  [ -f "$f" ] || { echo "no $f"; exit 1; }
done

# 1. the budget
n=$(( $(wc -c < "$a") + $(wc -c < "$c") ))
[ "$n" -le "$budget" ] || missing="$missing always-loaded:${n}b>${budget}b"

# 2. nothing read-on-demand is imported into the always-loaded file
grep -q '^@' "$a" && missing="$missing agents-imports"

# The one import that is allowed is CLAUDE.md -> AGENTS.md, because AGENTS.md
# is already in the budget above. Any second import is not.
i=$(grep -c '^@' "$c" || true)
[ "${i:-0}" -le 1 ] || missing="$missing claude-imports:$i"

# 3. tool docs are referenced, not inlined
if grep -qE '(cat|sed -n|head|awk)[^|]*"\$_doc"' core/cmd/session.sh 2>/dev/null; then
  missing="$missing tool-doc-inlined"
fi

[ -z "$missing" ] && exit 0
echo "always-loaded context grew:$missing"
echo "  every byte here is re-read on every request of every session."
echo "  see .leo/plans/C5-benchmark/RESULTS.md for what that costs."
exit 1
```
