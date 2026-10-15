# Rules

<!-- One rule per lesson learned, written the day something broke.

     A rule earns its place by having cost something. "Prefer X" is a
     preference and belongs in a style guide; a rule names a thing that
     actually went wrong, so the next person can tell the difference between
     taste and scar tissue.

     Read on demand. `AGENTS.md` carries only the handful an agent must know
     before it acts. -->

## How to write one

    ### <SHORT-NAME> — MUST / MUST NOT <the rule in one line>

    **What went wrong.** The real incident. What broke, what it cost, how
    long it took to find.

    **How to comply.** Concretely. What to do instead.

    **How to check.** The command, grep or test that catches a violation —
    or "by reading", honestly, if there is no mechanical check.

## Rules

### EXAMPLE — MUST NOT commit without the manifest in the message

**What went wrong.** A change landed with a one-line subject. Eight months
later a line in it caused an outage, and `git blame` led to a commit that
said "fix edge case" and named neither the task nor the reason. Two hours
went into rediscovering something that was known when it was written.

**How to comply.** The manifest table goes in the commit message body. Every
hunk, its task, why it exists, what breaks without it.

**How to check.** `git show <sha>` — if the body has no table, the rule was
broken.

<!-- Delete the example once you have written a real one. -->
