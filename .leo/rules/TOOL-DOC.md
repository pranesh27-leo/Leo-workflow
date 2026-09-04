# MUST NOT name a capability with no instruction file

MUST: every name in `BUILTIN_CAPS` has a `templates/tools/<name>.md`, every
file in `templates/tools/` names a capability, and `core/cmd/init.sh` installs
them.

`leo session` prints `instructions: .leo/tools/<name>.md` for every enabled
capability, and `.leo/workflow.md` tells the agent to read that file before
using the tool. A capability whose doc does not exist prints no pointer and the
agent uses the tool with none of the prerequisites — which is the state this
whole change existed to fix.

A doc that ships but is never installed is worse: it exists in the repository
leo was cloned from and in no repository leo is used in.

Learned from: `graph_advice` named MCP tool names for a release while the MCP
wire returned `Cannot read properties of undefined` on every call. Nothing
failed — the adapter loaded, the tests passed, the capability reported
installed — and the agent simply concluded the tool was broken. The knowledge
that would have fixed it in one line had nowhere to live.

## Verify

```sh
caps=$(sed -n 's/^BUILTIN_CAPS="\(.*\)"/\1/p' core/lib.sh)
bad=""

# A capability with no doc: the pointer never prints.
for n in $caps; do
  [ -f "templates/tools/$n.md" ] || bad="$bad $n:no-doc"
done

# A doc with no capability: it is installed into every repo and read by nobody.
for f in templates/tools/*.md; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .md)
  printf '%s\n' $caps | grep -qx "$n" || bad="$bad $n:doc-with-no-capability"
done

# And that init actually copies them, rather than leaving them in $LEO_HOME.
grep -q 'tools/\$_cap.md' core/cmd/init.sh || bad="$bad init:does-not-install"

[ -z "$bad" ] && exit 0
echo "tool docs broken:$bad"
exit 1
```
