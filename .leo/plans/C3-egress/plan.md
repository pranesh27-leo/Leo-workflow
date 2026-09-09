# Plan: prove no tool sends source off this machine

Created: 2026-09-08

## Goal
leo names seven capabilities and installs six third-party tools. Any of them
could read the repository and post it somewhere, and nothing in leo currently
says which do. Read each tool's source, give every one a one-line egress
verdict in its `.leo/tools/*.md`, and add a rule so a capability without a
verdict fails `leo check`.

## Non-goals
- Not an audit of leo itself. leo makes no network call; that is C2's build
  test to keep true, not this change's job.
- Not about your coding agent. Claude sees the code by definition -- the
  question here is only whether a *third party* server does.
- No sandboxing, no firewall rules, no egress proxy. This change produces
  knowledge and a rule that keeps it current, not enforcement at runtime.
- No vendoring of the tools themselves.

## Wrong-change signal
A verdict is written from a README rather than from the tool's source. The
entire value here is that someone actually read the code; a verdict copied
from marketing text is worse than no verdict, because it is trusted.

## The three verdicts

    Egress: none            runs locally, no socket opened
    Egress: install only    fetched once over the network, then local
    Egress: sends source    the tool transmits repository content -- to where

`graph` (codebase-memory-mcp) and `caveman` are the two expected to be
interesting. serena, rtk and headroom are expected local. ponytail is a
markdown ruleset and cannot send anything.

## Tasks

| #  | Task                                                    | Files                       | Est LOC | Status  |
|----|---------------------------------------------------------|-----------------------------|---------|---------|
| T1 | rule: every tool doc carries an Egress: line             | .leo/rules/TOOL-EGRESS.md   | 40      | pending |
| T2 | read serena, rtk, headroom sources; record verdicts      | templates/tools/            | 30      | pending |
| T3 | read graph and caveman sources; record verdicts          | templates/tools/            | 40      | pending |
| T4 | ponytail and tdd verdicts; session prints the verdict    | core/cmd/session.sh         | 35      | pending |
| T5 | findings report -- what was read, what was found         | .leo/plans/C3-egress/AUDIT.md | 60    | pending |

## Budget
est: 240 LOC
