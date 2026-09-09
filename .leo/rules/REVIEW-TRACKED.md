# MUST NOT gitignore the reviews

MUST NOT: `.leo/reviews/` — or anything matching it — is ever added to
`.gitignore` by `leo init`.

The plan, the manifest, the session and the task files are gitignored on
purpose: every one of them ends up *inside* the commit message it describes, so
the file is working state and the record is in git either way.

A review has no such home. It is written about a commit that already exists,
and that commit's message was sealed before the review was opened. The file in
`.leo/reviews/` is the only copy of cycle two there will ever be.

Learned from the pattern rather than an incident, which is the cheap way to
learn it: `leo init` appends to `.gitignore` from a list, every other `.leo/`
artefact is on that list, and adding one more looks like consistency. It would
delete the entire output of cycle two from every repository that ran `leo init`
afterwards, and no test anywhere would fail.

## Verify

```sh
grep -n 'reviews' core/cmd/init.sh | grep -q '_ignore' && {
  echo "core/cmd/init.sh gitignores the reviews — they are the only copy"
  exit 1
}

# And in this repository, right now.
if [ -f .gitignore ] && grep -qE '^\.leo/reviews' .gitignore; then
  echo ".gitignore hides .leo/reviews — the record of every review is lost"
  exit 1
fi
exit 0
```
