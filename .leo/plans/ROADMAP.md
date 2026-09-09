# Roadmap

Five changes, each with its own grill, plan, tasks and commit. Ordered so the
cheap and the unknown come first: the licence is ten minutes, and the egress
audit is the one whose findings could change everything after it.

| ID | Change                                   | Why it is here                                        | Status      |
|----|------------------------------------------|-------------------------------------------------------|-------------|
| C1 | MIT licence                              | The repo has no LICENSE; nobody can legally use it     | done        |
| C2 | Build a single-file leo, vendor it        | Clone -> build -> drop one file in the working repo    | built       |
| C3 | Security audit (leo's shell + tool egress)| Deferred by the developer, 2026-09-08                  | deferred    |
| C4 | Grill every task; AGENTS.md that binds    | Weak models skip the workflow entirely today           | built       |
| C5 | Token benchmark against real Claude counts| Built; needs a key to produce numbers                  | built       |

| C6 | Manifest staleness is undetectable       | Found 2026-09-09 while benchmarking                    | pending     |
| C7 | Spend fewer turns; quiet check           | Cost is quadratic in turns, not linear in bytes        | built       |
| C8 | Take the cap off the grill               | "3-10 questions" contradicted "no cap" in one section  | done        |
| C9 | Make the documents describe the tool     | Five changes landed; the documents did not keep up     | done        |
| C10| A review cycle: read a commit, never fix  | The author is the one reviewer whose opinion is spent  | built       |

C6, found the hard way: `leo scan` refuses to overwrite an existing manifest
("finish or delete it first"), which is right. But `leo check` then reports
"N hunk(s) not reviewed" against a manifest that may predate half the working
tree, and says nothing about the mismatch. In this session that understated a
72-hunk change as 27 for three turns, and it only surfaced because someone
looked at the row list. `leo scan` writes a `Base:` line; `leo check` could
compare the manifest's mtime and base against the current tree and say
"manifest is older than 14 changed files" instead of a confidently wrong
number. Nothing in leo currently notices.

C3 was split before it was deferred: the audit of leo's own shell (it sources
`.leo/integrations/*.sh` and executes shell out of `.leo/rules/*.md`, so a
hostile repository runs code the moment you type `leo check`) is a separate
question from whether serena or the code graph ship your source anywhere.
Neither has been done.

"built" means it works and its tests pass. It does not mean committed --
committing is the developer's.

Plans live in `.leo/plans/<id>-<slug>/plan.md`. They are committed, on purpose:
a plan you cannot share or reread later is a plan you rewrite from memory.

## The loop these follow

    grill -> plan -> task -> subtask -> build -> manifest -> commit

Seven stages now, not six. `subtask` was added because a parent task that turns
out to hold three decisions needs somewhere to record all three.
