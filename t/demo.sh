#!/usr/bin/env bash
# The demo. Each scene is one of the problems an agent causes, sent through
# the real hook with the JSON payload Claude Code and Codex really send. No
# model is involved: the agent's lines below are written out, so the demo is
# the same every run and shows the harness, not luck.
#
#   bash t/demo.sh
#
# Scenes 4 and 5 show what the loop asks the agent to write. No hook checks
# those, and the scene says so.

set -u
HOME_DIR=$(cd -P "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/leo-demo.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
P="$TMP/shop-api"; mkdir -p "$P" && cd "$P"
SESSION="demo$RANDOM"

# A small project to work in.
git init -q 2>/dev/null || mkdir -p .git
node "$HOME_DIR/bin/leo.js" init >/dev/null 2>&1
sed -i.bak 's/^\( *Lines: *\)[0-9]*/\1150/' AGENTS.md && rm -f AGENTS.md.bak
mkdir -p src
printf '{\n  "name": "shop-api",\n  "dependencies": { "express": "^4.19.0" }\n}\n' > package.json
cat > src/client.js <<'EOF'
const MAX_RETRIES = 3;

async function get(url) {
  for (let i = 0; i < MAX_RETRIES; i++) {
    const res = await fetch(url);
    if (res.ok) return res.json();
  }
  throw new Error('gave up after ' + MAX_RETRIES + ' tries: ' + url);
}

module.exports = { get };
EOF
H="$P/.agents/hooks"

# ------------------------------------------------------------- helpers
bold=$(printf '\033[1m'); red=$(printf '\033[31m'); grn=$(printf '\033[32m'); dim=$(printf '\033[2m'); off=$(printf '\033[0m')
[ -t 1 ] || { bold=; red=; grn=; dim=; off=; }

scene() { printf '\n%s━━ %s%s\n%s%s%s\n' "$bold" "$1" "$off" "$dim" "$2" "$off"; }
show()  { printf '%s\n' "$1" | fold -s -w 68 | sed "s/^/$2/"; }
reason() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{if(!s.trim())return;const j=JSON.parse(s);process.stdout.write((j.hookSpecificOutput&&j.hookSpecificOutput.permissionDecisionReason)||j.reason||"")})'; }

says() {  # the agent's reply -> the evidence hook's verdict
  printf '\n  %sagent says%s  %s\n' "$bold" "$off" "$1"
  out=$(node -e 'process.stdout.write(JSON.stringify({hook_event_name:"Stop",cwd:process.argv[1],session_id:"ev"+Math.random(),last_assistant_message:process.argv[2]}))' "$P" "$1" | node "$H/check-evidence.js" | reason)
  if [ -n "$out" ]; then
    printf '  %s✗ sent back%s\n' "$red" "$off"
    show "$(printf '%s' "$out" | sed -n '2,/^Open the files/p' | grep '^- ' | sed 's/^- //')" '              '
  else
    printf '  %s✓ passes%s\n' "$grn" "$off"
  fi
}

did() {  # tool, tool_input -> through the trace, as the runtime would after the call
  node -e 'process.stdout.write(JSON.stringify({hook_event_name:"PostToolUse",cwd:process.argv[1],session_id:process.argv[2],tool_name:process.argv[3],tool_input:JSON.parse(process.argv[4]),tool_response:{type:process.argv[5]||"update"}}))' "$P" "$SESSION" "$1" "$2" "${3:-update}" | node "$H/trace.js"
}

printf '%sleo %s, the demo%s\n' "$bold" "$(cat "$HOME_DIR/VERSION")" "$off"
printf '%sA project with src/client.js and express. Every verdict below\ncomes from the hook in .agents/hooks/, fed the payload the runtime sends.%s\n' "$dim" "$off"

# =====================================================================
scene '1. Hallucination: it explains code that is not there' \
  'check-evidence.js, at the end of every reply'
says 'Retries back off exponentially, in `src/retry.js:14`.'
says 'Retries stop after 5 tries: `src/client.js:1` `const MAX_RETRIES = 5;` (verified)'
says 'Retries stop after 3 tries at `src/client.js:1` (verified).'
says 'Retries stop after 3 tries: `src/client.js:1` `const MAX_RETRIES = 3;` (verified). There is no backoff: unknown whether the caller adds one.'

# =====================================================================
scene '2. What did it do at each step?' \
  'trace.js, after every tool call. Written by the runtime, not by the agent'
mkdir -p .agents/goals/G1
did Read "{\"file_path\":\"$P/src/client.js\"}"
did Grep '{"pattern":"MAX_RETRIES|backoff","path":"src"}'
did Edit "{\"file_path\":\"$P/src/client.js\",\"old_string\":\"    if (res.ok) return res.json();\",\"new_string\":\"    if (res.ok) return res.json();\\n    if (res.status < 500) break;\\n    await sleep(2 ** i * 100);\"}"
did Write "{\"file_path\":\"$P/src/sleep.js\",\"content\":\"const sleep = (ms) => new Promise((r) => setTimeout(r, ms));\\nmodule.exports = { sleep };\\n\"}" create
did Bash '{"command":"npm test"}'
# The reply ends here: under budget, so it passes and the count resets.
node -e 'process.stdout.write(JSON.stringify({hook_event_name:"Stop",cwd:process.argv[1],session_id:process.argv[2]}))' "$P" "$SESSION" | node "$H/budget.js" >/dev/null
printf '\n'
sed -n '/^| #/,$p' .agents/goals/G1/trace.md | sed 's/^/  /'
printf '\n  %sThe agent said it "added backoff". The trace also shows it read\n  client.js and searched for MAX_RETRIES first, and that it created\n  sleep.js, a new file. That is the one to ask about.%s\n' "$dim" "$off"

# =====================================================================
scene '3. Too much code to understand before the next prompt' \
  'budget.js, at the end of every reply. Lines: 150 in AGENTS.md'
printf '\n  %sagent writes%s src/cache.js (190 lines) and edits src/client.js (+24 -6)\n' "$bold" "$off"
body=$(node -e 'process.stdout.write(Array.from({length:190},(_,i)=>"// line "+i).join("\n")+"\n")')
did Write "$(node -e 'process.stdout.write(JSON.stringify({file_path:process.argv[1],content:process.argv[2]}))' "$P/src/cache.js" "$body")" create
did Edit "$(node -e 'process.stdout.write(JSON.stringify({file_path:process.argv[1],old_string:"a\n".repeat(6),new_string:"b\n".repeat(24)}))' "$P/src/client.js")"
out=$(node -e 'process.stdout.write(JSON.stringify({hook_event_name:"Stop",cwd:process.argv[1],session_id:process.argv[2]}))' "$P" "$SESSION" | node "$H/budget.js" | reason)
printf '  %s✗ sent back%s\n' "$red" "$off"; show "$out" '              '
printf '\n  %sagent sends%s the reading guide, not more code %s(its words; the hook only asks)%s:\n' "$bold" "$off" "$dim" "$off"
cat <<'EOF'
     1  src/client.js:7   stops retrying on 4xx          Source: grill
     2  src/cache.js:12   evicts oldest after 500 keys   Source: default  ← read
     3  src/cache.js:40   get(url), same shape as        Source: pattern src/client.js:3
                          client.get
     4  src/cache.js:60+  130 lines of get/set/has       Source: default  ← read
EOF
out=$(node -e 'process.stdout.write(JSON.stringify({hook_event_name:"Stop",cwd:process.argv[1],session_id:process.argv[2]}))' "$P" "$SESSION" | node "$H/budget.js" | reason)
[ -z "$out" ] && printf '  %s✓ passes%s %s(it sends a reply back once, so it cannot loop)%s\n' "$grn" "$off" "$dim" "$off"

# =====================================================================
scene '4. Why did it write it this way?' \
  'AGENTS.md and the manifest. Advice the agent follows: no hook checks this one'
cat <<'EOF'

  Before any code, under the start line:
    ▶ Working on: T2 — back off between retries
      Approach: sleep 2^i × 100 ms between tries, give up on 4xx
      Rejected: a retry library: one new dependency for 3 lines
      Copying:  nothing: this shape is mine

  After the build, one row per hunk, with where its shape came from:
    | Hunk             | Why                  | Source   |
    | src/client.js:7  | a 4xx will not heal  | grill    |
    | src/client.js:8  | wait 100, 200, 400ms | default  |
    | src/sleep.js:1   | a sleep helper       | default  |

  "default" is the honest answer to "why this way?": nobody asked for it
  and no code here showed it. The 100 ms is a guess, and nobody asked for
  a new file. Those are the two rows you read.
EOF

# =====================================================================
scene '5. Do you understand it, before you say yes?' \
  'review.md, before the green signal. Advice: the developer can answer skip'
cat <<'EOF'

  Read this first:  src/client.js:8, then src/sleep.js:1
  Your understanding:
    Q1  A 404: how many requests does get() send?
        you:  1        code: 1, the 4xx break (src/client.js:7)        ✓
    Q2  A 503 three times: how long does get() wait in total?
        you:  300 ms   code: 700 ms. It also waits after the last try
                       (src/client.js:8, inside the loop)              ✗
        → a wrong answer finds the bug nobody reviewed: 400 ms wasted.
          It goes in Findings before "Is this the result you wanted?"
EOF

printf '\n%sWhat is enforced, and what is advice:%s\n' "$bold" "$off"
cat <<'EOF'
  enforced by the runtime   1 evidence · 2 trace · 3 budget
  advice the agent follows  4 decision lines + Source · 5 the questions
                            no commit, no install, no secrets: standing
                            orders you can lift for one request
EOF
