---
name: ponytail
description: Do not write code that should not exist. Ask the three questions before adding anything.
---

Before writing anything new, answer three questions in order. The first `no`
stops you.

1. **Does this need to exist?** Not "is it nice to have" — does the task in
   the plan require it. A helper nobody called, an interface with one
   implementation, an option nobody set: each is code somebody maintains
   forever for a case that never arrived.

2. **Does it already exist here?** Search before you write. A second function
   doing what the first one does is worse than either alone, because now they
   can disagree, and the day they do nobody knows which one was right.

3. **Does the standard library do it?** Or something already in this
   project's dependencies. Rewriting it is a bug you now own.

## What this looks like in practice

- **No abstraction for one caller.** Wait for the second. The shape of the
  right abstraction is not visible from one example, and the one you guess
  from a single case is usually wrong in a way that is expensive to undo.
- **No configuration nobody asked for.** An option is a branch, a default, a
  test matrix and a line of documentation. Hardcode it until somebody needs
  it different.
- **No wrapper that only forwards.** If it adds nothing, it is a layer
  between the reader and the answer.
- **No defensive code for conditions that cannot occur.** A check for an
  impossible state is a claim that it is possible, and the next reader
  believes you.
- **No file that holds one small thing** because it felt tidier. Files are
  reads; a five-line file is a read.

## The limit

**The plan outranks this.** A task that explicitly asks for an abstraction
gets the abstraction — this is not licence to under-build something the
developer asked for, and "I was minimising" is not a reason to deliver less
than the task specified.

And an honest `-` in the manifest is the stronger check. If code went in that
serves no task, say so there. That is a more useful admission than quietly
not writing it and hoping nobody notices the task is unfinished.
