#!/usr/bin/env bash
# bench.sh — what leo's record actually costs, in real Claude tokens.
#
# leo's claim is that a manifest is cheaper to read than a diff, and a task
# file cheaper than the files it describes. Both were unmeasured until this
# existed. This counts them with Anthropic's /v1/messages/count_tokens, so the
# number is a real tokenizer's, not chars/4.
#
# THIS IS A DEVELOPMENT TOOL. It is not part of `leo check`, it is not in the
# smoke suite, and nothing runs it as a side effect. It needs a network and a
# key, and both would make the test suite fail on a plane.
#
# It runs on fixtures in this repository and on nothing else. leo spends a
# whole change proving no tool ships your source anywhere; a benchmark that
# posted your diff to an API to prove leo saves you money would be the joke
# writing itself.
set -u

# Count against the model you actually work under, because the count is
# model-specific: Claude Opus 4.7 and later use a newer tokenizer that returns
# roughly 30% more tokens for the same text than earlier models. A number
# measured on the wrong model is not a smaller number, it is a wrong one.
MODEL="${BENCH_MODEL:-claude-opus-5}"
ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
FIX="$ROOT/t/fixtures"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "skipped: no ANTHROPIC_API_KEY in the environment."
  echo
  echo "  This benchmark calls Anthropic's count_tokens endpoint, which needs a"
  echo "  key and a network. It is a development tool and never runs as part of"
  echo "  leo check or the smoke suite, so skipping is a normal outcome:"
  echo
  echo "      ANTHROPIC_API_KEY=sk-... bash t/bench.sh"
  echo
  echo "  A Claude Pro or Max subscription does NOT include an API key -- the"
  echo "  API is a separate account with separate billing. Create one at"
  echo "  console.anthropic.com, then Settings -> API keys."
  echo
  echo "  Counting tokens is free of charge. It is rate limited by usage tier"
  echo "  (5,000 requests/minute at the lowest), and this run makes 12 calls,"
  echo "  so the benchmark costs nothing to run."
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "skipped: no curl"; exit 0; }

# count <file> — real tokens for the file's contents, via count_tokens.
#
# The JSON is built with a here-doc and a python one-liner rather than by
# pasting the file into a string: a diff is full of quotes, backslashes and
# newlines, and hand-rolled JSON escaping would corrupt exactly the large
# inputs this is meant to measure.
count() {
  [ -f "$1" ] || { echo 0; return 0; }
  _body=$(python3 -c '
import json,sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
print(json.dumps({"model": sys.argv[2],
                  "messages": [{"role": "user", "content": text or "(empty)"}]}))
' "$1" "$MODEL") || { echo 0; return 0; }

  _out=$(printf '%s' "$_body" | curl -sS --max-time 60 \
      https://api.anthropic.com/v1/messages/count_tokens \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      --data-binary @- 2>/dev/null)

  printf '%s' "$_out" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); sys.exit(0)
# An error body is not a count. Print 0 and let the caller report a dash
# rather than silently folding an API failure into a flattering ratio.
print(d.get("input_tokens", 0) if isinstance(d, dict) else 0)
'
}

# row <label> <before-file> <after-file>
row() {
  _b=$(count "$2"); _a=$(count "$3")
  if [ "${_b:-0}" -le 0 ] || [ "${_a:-0}" -le 0 ]; then
    printf '  %-28s %10s %10s %10s\n' "$1" "${_b:-?}" "${_a:-?}" "-"
    return 0
  fi
  _r=$(python3 -c "print(f'{$_b/$_a:.1f}x')")
  printf '  %-28s %10s %10s %10s\n' "$1" "$_b" "$_a" "$_r"
}

if [ ! -d "$FIX/large" ]; then
  echo "skipped: no fixtures."
  echo
  echo "  They are derived from this repository's own history and gitignored,"
  echo "  because git already holds every byte they are made of:"
  echo
  echo "      bash t/fixtures/generate.sh"
  exit 0
fi

echo "leo token benchmark"
echo "  model: $MODEL"
echo "  date:  $(date -u '+%Y-%m-%d %H:%M UTC')"
echo
printf '  %-28s %10s %10s %10s\n' "comparison" "before" "after" "ratio"
printf '  %-28s %10s %10s %10s\n' "----------" "------" "-----" "-----"

for _f in "$FIX"/*; do
  [ -d "$_f" ] || continue
  _n=$(basename "$_f")
  row "$_n: diff -> manifest"  "$_f/diff.txt"    "$_f/manifest.md"
  # Deliberately not context.txt: that is the whole change's files, and the
  # task file covers one task. Comparing them would flatter leo by a factor of
  # however many tasks the change had.
  row "$_n: files -> task"     "$_f/taskcontext.txt" "$_f/task.md"
done

echo
echo "  before = what you would have read without leo."
echo "  after  = what leo has you read instead."
echo "  A ratio below 1.0x means leo cost you tokens on that input. Report it."
