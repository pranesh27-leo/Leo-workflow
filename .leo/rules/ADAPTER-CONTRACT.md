# MUST NOT add an integration that does not answer the contract

MUST: every file in `core/integrations/` defines `<name>_present` and
`<name>_hint`, and `<name>` appears in `BUILTIN_CAPS` in `core/lib.sh`.

`core/lib.sh` sources that directory blind — same as `core/cmd/`, no registry —
so an adapter that is misnamed, or names a capability `BUILTIN_CAPS` never lists, loads
cleanly and does nothing. Nothing fails; the capability just quietly reports as
one leo has no adapter for.

Learned from: `ponytail_present` ended in `grep -q pattern missing-file`, which
exits **2** — the code `cap_present` uses for "leo has no adapter". A real
adapter reported as an unsupported capability, and the display was wrong with
every check passing. `cap_present` now collapses the adapter's status to 0 or 1;
this rule catches the other half, an adapter that is never reachable at all.

`<name>_advice` stays optional: there is not always something useful to say.

## Verify

```sh
caps=$(sed -n 's/^BUILTIN_CAPS="\(.*\)"/\1/p' core/lib.sh)
bad=""
for f in core/integrations/*.sh; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .sh)
  grep -q "^${n}_present()" "$f" || bad="$bad $n:no-_present"
  grep -q "^${n}_hint()"    "$f" || bad="$bad $n:no-_hint"
  printf '%s\n' $caps | grep -qx "$n" || bad="$bad $n:not-in-CAPS"
done
# And the reverse: a name in BUILTIN_CAPS with no adapter behind it. leo would
# name the capability, find no functions for it, and report it as one it has no
# adapter for -- true, but the cause is a typo in a list, not a missing tool.
for n in $caps; do
  [ -f "core/integrations/$n.sh" ] || bad="$bad $n:no-adapter-file"
done

[ -z "$bad" ] && exit 0
echo "adapter contract broken:$bad"
exit 1
```
