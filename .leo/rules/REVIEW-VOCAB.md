# MUST NOT let the review vocabulary drift between the file and the code

MUST: `blocker`, `improvement`, `nit`, `open`, `fixed` and `waived` are the
whole vocabulary of the findings table, and each word appears in all three
places that depend on it — the code that parses it (`core/cmd/review.sh`), the
rubric that teaches it (`templates/review/STANDARDS.md`), and the template a
reviewer fills in (`templates/review.md`).

`leo review --close` is the gate of cycle two, and it reads exactly two columns
of a markdown table. That works only because the words are closed. Add a
severity to the standards and not to the parser and the gate rejects it as
unreadable — noisy, but safe. Add one to the *parser* and not the standards and
the failure is the dangerous direction: a severity nobody was taught to use,
which therefore never blocks anything.

Learned from the shape of the bug this file already prevented once. `review_state`
and `review_pick` were derived from the same predicate, so a review that met
every closing condition became invisible to `--close` — it could never be
closed, and nothing failed. Anything in cycle two that reads its own file back
has this failure mode: the check passes because the thing it checks is gone.

## Verify

```sh
bad=""
for w in blocker improvement nit; do
  grep -q "\"$w\""  core/cmd/review.sh              || bad="$bad parser:$w"
  grep -q "\`$w\`"  templates/review/STANDARDS.md   || bad="$bad standards:$w"
  grep -q "$w"      templates/review.md             || bad="$bad template:$w"
done
for w in open fixed waived; do
  grep -q "\"$w\""  core/cmd/review.sh              || bad="$bad parser:$w"
  grep -q "$w"      templates/review.md             || bad="$bad template:$w"
done

# The two the state machine turns on. `review_state` calling these anything
# else is how a closed review reads as open forever.
grep -q 'review_count "$1" blocker open' core/lib.sh || bad="$bad lib:blocker-open"

[ -z "$bad" ] && exit 0
echo "review vocabulary drifted:$bad"
exit 1
```
