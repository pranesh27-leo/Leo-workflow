# Review standards

What a review here judges, and in what order. This file is the rubric: `leo
review` gathers the evidence, and the reviewer — human or agent — argues
against *this*, not against taste.

It is installed into your repository rather than read from leo's own, for the
same reason `.leo/workflow.md` is a copy: your standards are yours. Delete a
section that does not apply to you, and add the ones your incidents taught you.

## The mandate

**Net positive, not perfect.** The question is whether the change leaves the
codebase healthier than it found it. A change that is a clear improvement does
not get blocked for imperfections, and a reviewer hunting for something to say
is costing more than they add.

**Substance over style.** Anything a formatter or a linter can settle is not a
review finding — it is a missing tool, and the fix is the tool. Spend the
review on what no tool can see: design, correctness, security, the interaction
between this change and the rest of the system.

**Grounded, not preferred.** Every finding names the principle or the fact
behind it, and a failure it would actually cause. "I would have written it
differently" is not a finding. If you cannot say what breaks, it is a nit.

**Scope is already answered.** `.leo/manifest.md` says whether each hunk was
asked for. Do not re-litigate it here — a review that rediscovers scope creep
is reading the wrong file.

## The order

Reviewed top to bottom. The order is deliberate: a design error found at stage
1 makes every finding below it moot, so finding it late is the expensive
mistake.

### 1. Design and integrity

- Does it fit the architecture that is already here, or does it fight it?
- Is the change atomic — one cohesive purpose — or several bundled together?
- Is there a materially simpler solution that meets the same requirement?
- Are the abstraction boundaries the ones the domain has, or invented ones?
- Does it add a concept the codebase will now have two of?

### 2. Correctness

- Does it do what the task said it would? Read the task, then the code.
- Edge cases: empty, zero, one, missing, malformed, very large, concurrent.
- Error paths: is every failure either handled or deliberately propagated?
  A swallowed error is a finding, every time.
- State and lifetime: partial writes, retries that are not idempotent, cleanup
  that does not run on the failure path.
- Concurrency: shared mutable state, check-then-act races, ordering assumed
  and not enforced.

### 3. Security — non-negotiable

Nothing here is ever traded for velocity. A blocker in this section is a
blocker regardless of what else the change is worth.

- Untrusted input reaching an interpreter: SQL, shell, template, path,
  deserialiser, regex built from input.
- Output that is not escaped for where it lands.
- Authentication and authorisation checked on every new entry point — and
  checked for *this* actor, not merely that some actor is logged in.
- Secrets: none committed, none logged, none in an error message or a URL.
- Data exposure: what does this add to logs, traces, responses and stack
  traces that was not there before?
- Cryptography: standard library, standard construction, no invented scheme.

### 4. Tests

- Does a test exist that fails without this change? If not, say so.
- Do the tests cover the failure modes, or only the happy path?
- Is the test asserting behaviour, or asserting the implementation it was
  written next to?
- Would this test have caught the bug this change fixes?

### 5. Maintainability

- Will this read clearly to someone who arrives in a year with no context?
- Names: do they say what the thing is, in the vocabulary of the domain?
- Comments explain *why*. A comment restating the code is a finding.
- Nesting and control flow: can the reader hold it in their head?
- Duplication that is now the third copy.

### 6. Performance and scale

Only where it is real. A hot path, a loop over a collection that grows, a
query per row, an allocation per request. Speculative optimisation is itself a
finding — it costs clarity and buys nothing measured.

- Work inside a loop that could be done once, especially I/O.
- Queries: N+1, missing index, unbounded result set, no pagination.
- Unbounded growth: caches with no eviction, buffers with no limit.
- Payload and bundle size where a user waits on it.

### 7. Dependencies and interfaces

- Is a new dependency necessary, maintained, and licensed compatibly? Weigh it
  against the code it replaces, not against zero.
- Is a public interface changed in a way that breaks a caller? Name the caller.
- Are the docs, config and migrations that this change implies actually here?

## Severity

Three levels, and the vocabulary is fixed because `leo review --close` reads it.

| Severity | Means | Effect |
|----------|-------|--------|
| `blocker` | Must not ship as it stands: security, data loss, incorrect behaviour, an architectural regression that gets harder to undo later. | holds the review open until it is fixed or waived |
| `improvement` | Should be done, does not have to be done now. Name it, and let the developer decide. | Reported, never blocks |
| `nit` | Optional polish. Costs a line to write and a line to fix. | Reported, never blocks |

A blocker leaves the table one of two ways: `fixed`, or `waived` by the
developer. Waiving is theirs, never the reviewer's, and it lands in the commit
message where the next person will read it.

**Do not inflate.** A reviewer who marks improvements as blockers gets ignored
on the one that mattered. **Do not deflate either** — the whole apparatus is
worth nothing if a real security finding is filed as a nit to avoid an
argument.

## Writing a finding

One row of the table, and it earns its place by being actionable:

- **Where** — `file:line`, not "in the auth code".
- **Finding** — what is wrong, stated so it can be disagreed with.
- **Why it matters** — the failure it causes or the principle it breaks. If
  this cell is hard to fill in, the row is a nit or is nothing.

Say what to do about it, not just what is wrong. And where a finding is a
judgement call, say that it is one — the developer knows things the reviewer
does not.

## When a finding recurs

If the same finding shows up in a third review and a shell command could catch
it, stop writing it in reviews and write `.leo/rules/<NAME>.md` instead. That
is the point of rules: a lesson that runs for free on every `leo check`, long
after the reviewer who learned it has gone.
