#!/usr/bin/env bash
# bench-session.sh — what leo actually cost, from real sessions.
#
# t/bench.sh measures artifacts: is a manifest smaller than a diff. That is a
# proxy, and a flattering one -- it counts what leo saves and none of what leo
# spends. AGENTS.md loads on every request forever. workflow.md, the plan, the
# task file and the grill rounds are all tokens leo added. A manifest that is
# 8x smaller than its diff means nothing if the agent read the diff anyway.
#
# This measures the real thing: total tokens consumed by an actual session,
# from the transcripts Claude Code already writes to disk. No API key, no
# network, no estimate -- these are the counts the API itself reported.
#
#   ~/.claude/projects/<project-slug>/<session-id>.jsonl
#
# Sessions are classified by whether leo commands appear in them, so "with leo"
# and "without leo" are read off the record rather than remembered.
#
# THIS READS YOUR TRANSCRIPTS AND PRINTS NUMBERS. It sends nothing anywhere.
set -u

# --all compares every project on this machine, grouped by whether leo was
# used. That is observational, not an experiment -- different projects did
# different work -- but it is real usage at a sample size one repository cannot
# reach, and it is the only comparison available before someone runs the
# controlled A/B in PROTOCOL.md.
PROJECT="${1:-$(pwd)}"

python3 - "$PROJECT" <<'PY'
import json, os, sys, glob, re

# Claude Code slugs a project path by replacing every non-alphanumeric run
# with a dash. Derive it rather than asking, so this works from any repo.
# A session counts as "with leo" if it actually ran leo. Read off the record,
# not remembered: the whole point is not to trust anyone's recollection of
# which session had the workflow switched on.
LEO = re.compile(r'\bleo (scan|check|plan|task|session|commit|build|install|init)\b')

ALL = sys.argv[1] == '--all'

def scan(f):
    """One transcript -> its totals. Ground truth: these are the numbers the
    API reported for each turn, not an estimate of them."""
    t = dict(turns=0, inp=0, out=0, cr=0, cw=0, think=0, leo=0, first=None, last=None)
    for line in open(f, errors='replace'):
        try: rec = json.loads(line)
        except Exception: continue
        ts = rec.get('timestamp')
        if ts:
            t['first'] = t['first'] or ts
            t['last'] = ts
        msg = rec.get('message') or {}
        c = msg.get('content')
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get('type') == 'tool_use' \
                   and LEO.search(json.dumps(b.get('input') or {})):
                    t['leo'] += 1
        u = msg.get('usage')
        if not u: continue
        t['turns'] += 1
        t['inp']   += u.get('input_tokens', 0)
        t['out']   += u.get('output_tokens', 0)
        t['cr']    += u.get('cache_read_input_tokens', 0)
        t['cw']    += u.get('cache_creation_input_tokens', 0)
        t['think'] += (u.get('output_tokens_details') or {}).get('thinking_tokens', 0)
    return t

def med(xs):
    xs = sorted(xs)
    if not xs: return 0
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2

path = os.path.abspath(sys.argv[1] if not ALL else '.')
slug = re.sub(r'[^A-Za-z0-9]', '-', path)
d = os.path.expanduser(f'~/.claude/projects/{slug}')

if ALL:
    base = os.path.expanduser('~/.claude/projects')
    rows = []
    for proj in sorted(glob.glob(f'{base}/*')):
        for f in glob.glob(f'{proj}/*.jsonl'):
            t = scan(f)
            if t['turns'] < 20:   # too short to say anything about
                continue
            t['proj'] = os.path.basename(proj)
            rows.append(t)

    if not rows:
        print('no sessions long enough to compare'); sys.exit(0)

    A = [t for t in rows if t['leo']]      # with leo
    B = [t for t in rows if not t['leo']]  # without

    print('every project on this machine, grouped by whether leo was used')
    print(f'  {len(rows)} sessions of 20+ turns: {len(A)} with leo, {len(B)} without')
    print()
    hdr = f"  {'project':38} {'leo?':6} {'turns':>6} {'fresh/turn':>12} {'cached/turn':>13} {'out/turn':>10}"
    print(hdr); print('  ' + '-' * (len(hdr) - 2))
    for t in sorted(rows, key=lambda r: (0 if r['leo'] else 1, r['proj'])):
        n = t['turns']
        print(f"  {t['proj'][:38]:38} {(str(t['leo'])+'x' if t['leo'] else '-'):6} "
              f"{n:6d} {(t['inp']+t['cw']+t['out'])//n:12,} {t['cr']//n:13,} {t['out']//n:10,}")

    print()
    print('  medians across sessions (median, not mean: one 400k/turn session')
    print('  would otherwise decide the answer on its own)')
    print()
    for name, g in (('with leo', A), ('without leo', B)):
        if not g: continue
        print(f"  {name:12} fresh/turn {med([(t['inp']+t['cw']+t['out'])//t['turns'] for t in g]):9,.0f}"
              f"   cached/turn {med([t['cr']//t['turns'] for t in g]):11,.0f}"
              f"   out/turn {med([t['out']//t['turns'] for t in g]):7,.0f}")

    # Fresh and cached tokens do not cost the same, so a comparison that
    # reports them side by side says nothing about whether you spent more.
    # Weight them: Claude Opus 5 list price is $5/MTok input, cache writes
    # 1.25x that, cache reads 0.1x, output $25/MTok. The absolute dollars are
    # not the point -- a subscription is not billed this way -- but the
    # weighting is what turns two contradictory ratios into one answer.
    def cost(t):
        return (t['inp'] * 5 + t['cw'] * 6.25 + t['cr'] * 0.5 + t['out'] * 25) / 1e6

    print()
    for name, g in (('with leo', A), ('without leo', B)):
        if not g: continue
        print(f"  {name:12} price-weighted: ${med([cost(t)/t['turns'] for t in g]):.4f} per turn")
    if A and B:
        ka = med([cost(t)/t['turns'] for t in A])
        kb = med([cost(t)/t['turns'] for t in B])
        if ka:
            verdict = 'leo cheaper' if kb > ka else 'leo more expensive'
            print(f"  {'ratio':12} {kb/ka:.2f}x  ({verdict} per turn)")

        # The verdict turns on the cache-read multiplier, and it flips inside
        # the range of plausible values -- so print the sweep rather than one
        # number. A benchmark whose answer depends on an assumption must show
        # the assumption moving.
        print()
        print('  sensitivity to the cache-read price (the assumption above):')
        for mult in (0.05, 0.10, 0.20, 0.50, 1.00):
            f = lambda t: (t['inp']*5 + t['cw']*6.25 + t['cr']*5*mult + t['out']*25) / 1e6
            x = med([f(t)/t['turns'] for t in A]); y = med([f(t)/t['turns'] for t in B])
            if x:
                print(f"    cache read at {mult:4.2f}x input:  {y/x:5.2f}x  "
                      f"({'leo cheaper' if y > x else 'leo dearer'})")

    if A and B:
        fa = med([(t['inp']+t['cw']+t['out'])//t['turns'] for t in A])
        fb = med([(t['inp']+t['cw']+t['out'])//t['turns'] for t in B])
        ca = med([t['cr']//t['turns'] for t in A])
        cb = med([t['cr']//t['turns'] for t in B])
        print()
        print(f"  fresh tokens per turn:  {fb/fa:.2f}x  (>1 means leo used fewer)" if fa else '')
        print(f"  cached tokens per turn: {cb/ca:.2f}x  (>1 means leo used fewer)" if ca else '')

    print()
    print('  THIS IS NOT AN EXPERIMENT. Different projects, different tasks,')
    print('  different codebases, and leo was chosen for the ones it was used on')
    print('  rather than assigned. It cannot tell you what leo caused. For that,')
    print('  run the same task twice -- see .leo/plans/C5-benchmark/PROTOCOL.md.')
    sys.exit(0)

if not os.path.isdir(d):
    print(f"no transcripts for {path}")
    print(f"  looked in: {d}")
    sys.exit(0)

rows = []
for f in sorted(glob.glob(f'{d}/*.jsonl')):
    t = scan(f)
    if t['turns']:
        t['id'] = os.path.basename(f)[:8]
        rows.append(t)

if not rows:
    print(f"no sessions with usage data in {d}")
    sys.exit(0)

def fresh(t):  # tokens the model had to read or write anew
    return t['inp'] + t['cw'] + t['out']
def total(t):  # everything, cache re-reads included
    return t['inp'] + t['cw'] + t['cr'] + t['out']

print(f"sessions for {path}")
print(f"  {len(rows)} session(s), from {rows[0]['first'][:10]} to {rows[-1]['last'][:10]}")
print()
h = f"  {'session':9} {'leo?':5} {'turns':>6} {'fresh':>12} {'cache read':>14} {'output':>10} {'per turn':>10}"
print(h); print('  ' + '-' * (len(h) - 2))
for t in rows:
    tag = f"{t['leo']}x" if t['leo'] else "-"
    print(f"  {t['id']:9} {tag:5} {t['turns']:6d} {fresh(t):12,} {t['cr']:14,} {t['out']:10,} {total(t)//t['turns']:10,}")

with_leo = [t for t in rows if t['leo']]
without  = [t for t in rows if not t['leo']]
print()
print("  fresh      = input + cache writes + output. New tokens, full price.")
print("  cache read = context re-read each turn. Real tokens, ~10% of input price.")
print("  per turn   = everything / turns. The only number comparable across")
print("               sessions of different lengths.")

if with_leo and without:
    a = sum(total(t) for t in with_leo)  / sum(t['turns'] for t in with_leo)
    b = sum(total(t) for t in without)   / sum(t['turns'] for t in without)
    print()
    print(f"  with leo:    {a:12,.0f} tokens/turn  ({len(with_leo)} session(s))")
    print(f"  without leo: {b:12,.0f} tokens/turn  ({len(without)} session(s))")
    print(f"  ratio:       {b/a:12.2f}x" if a else "")
    print()
    print("  Treat this as an observation, not a result: different sessions did")
    print("  different work. For a claim you can defend, run the same task twice")
    print("  -- once with leo, once without -- and compare those two rows.")
else:
    have = "with leo" if with_leo else "without leo"
    print()
    print(f"  Every session here is {have}, so there is nothing to compare against.")
    print("  Run the same task in a session that does the opposite, then re-run this.")
PY
