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

Four things are checked, and they are the four levers:

1. **A byte budget** on the always-loaded pair. Bytes, not lines — a line cap
   is defeated by long lines, and the model pays for bytes.
2. **No imports** from `AGENTS.md`. An import makes a read-on-demand file
   always-loaded, which is the whole distinction collapsing.
3. **Tool docs are pointed at, never printed.** `leo session` prints a path;
   whoever needs the content opens it. Printing it would put seven files into
   context for a session that needed none of them.
4. **The template ships a placeholder tools block, never a filled one.**
   `leo agents` writes the real block into the repository's own `AGENTS.md`.
   A template that shipped an expanded block would put leo's own seven tools
   into the always-loaded context of every repository that ran `leo init`,
   including the ones with none of them installed.

## The budget was raised once, on purpose

2400 -> 3000, when `leo agents`, `leo defer` and numbered plans landed. What
that 600 bytes bought, and why each line is there rather than in a file read on
demand:

- **The tools block marker.** It has to be in the template, or `leo agents`
  appends at the bottom of whatever the developer has written and the block
  drifts to a different place in every repository.
- **Deferral, in one sentence.** The failure it prevents is the expensive one:
  an agent that cannot do T3 marks it `done`, and the lie is in the commit
  message forever. Telling it about `leo defer` only in `.leo/workflow.md`
  means telling it at the moment it has already decided.
- **A new goal is a new plan.** Same shape. Without it, an agent asked for
  something unrelated amends the plan in flight, and the manifest then has
  hunks serving a goal the plan never declared.

Both of those are decisions an agent makes *before* it would have any reason
to open a file. That is the test for this budget, and it is the only one: a
line earns a place here if the mistake it prevents happens before the agent
would have read the file that explains it. Everything else goes on demand.

## Verify

```sh
budget=3000
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

# 4. the template's tools block is a placeholder, not content. `leo agents`
# fills it per repository; a filled one here would ship leo's own seven tools
# into every repo that ran `leo init`, installed or not.
if grep -q 'leo:tools begin' "$a"; then
  n=$(awk '/leo:tools begin/ { c = 1 } c { print } /leo:tools end/ { c = 0 }' "$a" \
      | wc -c | tr -d ' ')
  [ "${n:-0}" -le 300 ] || missing="$missing tools-block-filled:${n}b"
else
  missing="$missing no-tools-marker"
fi

[ -z "$missing" ] && exit 0
echo "always-loaded context grew:$missing"
echo "  every byte here is re-read on every request of every session."
echo "  see .leo/plans/C5-benchmark/RESULTS.md for what that costs."
exit 1
```
