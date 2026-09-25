# MUST NOT install an exit handler outside src/lib/exit.js

MUST: only `src/lib/exit.js` calls `process.on('exit')`. Everything else that
needs cleanup registers it with `atexitAdd`.

Under bash this rule existed because `trap` does NOT stack: the last EXIT trap
installed silently replaced every earlier one, so a command that installed its
own un-installed leo's — and leo's is what writes `SESSION.md` on the way out.

Node's `process.on('exit')` does stack, so that exact failure is gone. The rule
survives the port because the reason underneath it did not. An exit handler
cannot await anything, the session document is written from one, and a second
handler registered somewhere else runs in an order nobody declared — after the
document is written, against state it has already read. One place registers
it, and the ordering is then a fact rather than a coincidence.

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
hits=$(grep -rn "process\.on( *['\"]exit" src/ leo 2>/dev/null \
       | grep -v '^src/lib/exit\.js:' \
       | grep -v '^[^:]*:[0-9]*: *//')

[ -z "$hits" ] && exit 0
echo "exit handler outside src/lib/exit.js — the ordering stops being declared:"
printf '%s\n' "$hits"
echo "  use: atexitAdd(function () { ... })"
exit 1
```
