# Ponytail — generated-code minimisation

A ruleset, not a program. Before writing code: does the thing need to exist,
does it already exist, does the standard library do it?

It is detected by its ruleset being present in `AGENTS.md`, which is the form
that works with every agent. The plugin installs cannot be detected portably,
so if you installed it that way, add the ruleset too or read leo's MISSING as
a false negative.

## The plan outranks it

A task that asks for an abstraction gets the abstraction. Ponytail advises;
the plan decides, and `leo check` verifies against the plan.

Where it overlaps leo, leo already has teeth: the budget check and the
manifest's `If deleted` column push toward the same place, and an honest `-`
row in the manifest is the stronger check — it is a claim someone reads, not a
guideline someone recalls.

## Cost

About 2.5KB appended to `AGENTS.md`, which loads on every request. That is a
real cost paid on every turn, not a free one.
