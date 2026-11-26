# Understand Anything — a knowledge graph of the repository

[Egonex-AI/Understand-Anything](https://github.com/Egonex-AI/Understand-Anything),
MIT. A plugin that scans the project with a multi-agent pipeline and writes a
knowledge graph of every file, function, class and dependency to
`.ua/knowledge-graph.json` (or `.understand-anything/knowledge-graph.json` in
projects that already have that directory). Its skills then answer questions
from the graph.

It is a whole plugin, with agents, skills, scripts and a dashboard, so leo
does not vendor it. It is a tool, like the code graph.

Optional. Missing it is not an error: say so once and carry on.

## Install

**You do not run this.** Show it to the developer and let them decide.

    # Claude Code
    /plugin marketplace add Egonex-AI/Understand-Anything
    /plugin install understand-anything

    # Codex (and other agents): clones to ~/.understand-anything/repo
    curl -fsSL https://raw.githubusercontent.com/Egonex-AI/Understand-Anything/main/install.sh | bash -s codex

    # Windows (PowerShell)
    iwr -useb https://raw.githubusercontent.com/Egonex-AI/Understand-Anything/main/install.ps1 | iex

Then build the graph once per repository with `/understand` (Codex:
`$understand`). Re-running it is incremental.

## The skills that earn their place

    /understand-chat <question>     answer from the graph
    /understand-explain <file|fn>   deep-dive one file or function
    /understand-diff                what the current change touches
    /understand-onboard             an onboarding guide

Codex uses `$` instead of `/`.

## When

**Before answering a question about the repository**, when the graph exists.
Ask it **where** to look: which files, which functions, which edges (`calls`,
`imports`, `configures`) connect the thing asked about. That is the Locate
step of `.agents/skills/evidence/SKILL.md`, done faster.

**The graph is a lead, never evidence.** Its node summaries were written by
a model, and the graph was built at one commit (`project.gitCommitHash`).
Both can be wrong or stale. So:

- Never cite the graph. Open the source files it points at, read the lines,
  and cite **those** as `path:LINE`.
- If the graph's commit is not `HEAD`, the files changed since then are
  exactly where it is most likely wrong. `/understand-chat` checks freshness
  itself; say so when it reports the graph is stale.
- If the graph and the code disagree, the code is right. Say that the graph
  was wrong there.

**When it is not there**: no `.ua/` or `.understand-anything/` directory.
Do the Locate step by hand (grep, the code graph), and mention once that
`/understand` would build it.
