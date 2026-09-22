# MUST NOT install an EXIT trap outside core/lib.sh

MUST: only `core/lib.sh` calls `trap ... EXIT`. Everything else that needs
cleanup registers it with `leo_atexit_add`.

`trap` does not stack. The last EXIT trap installed silently replaces every
earlier one, and nothing anywhere reports that it happened. A command that
installs its own therefore un-installs leo's — and leo's is what writes
`SESSION.md` on the way out.

That failure is invisible in exactly the way that matters. The command still
works. Its own temp file is still deleted. The only symptom is that
`SESSION.md` quietly stops being current for *that command*, and the commands
most likely to want a cleanup trap are the long ones — `check`, `commit`,
`review`, `build` — which is to say the ones whose outcome is most worth
having on disk after a session drops.

Learned from writing the feature. Four files had their own EXIT trap when the
session document was added: `check`, `build`, `commit` and `review`. The first
two were found by reading; the second two were found by a test, after the
reading had already concluded there were none left.

`leo_atexit_add '<command>'` appends to a list the single handler runs. The
handler also preserves the exit status it was called with, which a hand-rolled
trap routinely does not.

## Verify

```sh
# Comments may discuss the pattern -- this rule is about code that runs it.
hits=$(grep -rn 'trap .*EXIT' core/ leo 2>/dev/null \
       | grep -v '^core/lib\.sh:' \
       | grep -v '^[^:]*:[0-9]*: *#')

[ -z "$hits" ] && exit 0
echo "EXIT trap outside core/lib.sh — it replaces leo's, silently:"
printf '%s\n' "$hits"
echo "  use: leo_atexit_add 'rm -f \"\$tmp\"'"
exit 1
```
