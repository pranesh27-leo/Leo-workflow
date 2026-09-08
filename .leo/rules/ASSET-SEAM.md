# ASSET-SEAM

MUST: nothing outside the seam in `core/lib.sh` reads leo's own install. No
file under `core/` may name `$LEO_HOME/templates`, `$LEO_HOME/VERSION` or
`$LEO_HOME/leo` directly — it goes through `tmpl_cat`, `tmpl_has`,
`leo_version` or `$LEO_SELF`.

`leo build` compiles a single-file leo that answers those four from itself.
The bundle has no source tree next to it, so a direct read works perfectly in
the clone and fails only for the person who vendored the bundle into their own
repository — the one place nobody is looking.

Learned from: every one of the five original call sites was correct and
obvious. `cp "$LEO_HOME/templates/$1" "$2"` is the natural way to write init,
and it is exactly what a bundle cannot do.

## Verify

```sh
# Comments may discuss the paths -- this rule is about code that reads them.
# core/cmd/build.sh is exempt, and is the only file that can be: it is the
# compiler. Reading the source tree is its entire job, and it is the reason
# every other file must not.
hits=$(grep -rn 'LEO_HOME/templates\|LEO_HOME/VERSION\|LEO_HOME/leo' \
         core/ leo 2>/dev/null \
       | grep -v '^core/cmd/build\.sh:' \
       | grep -v '^[^:]*:[0-9]*: *#')

# The seam itself is the one legitimate reader.
hits=$(printf '%s\n' "$hits" | grep -v 'leo_version() {\|tmpl_has()    {\|tmpl_cat()    {' | grep . || true)

[ -z "$hits" ] && exit 0
echo "asset read outside the seam:"
printf '%s\n' "$hits"
exit 1
```
