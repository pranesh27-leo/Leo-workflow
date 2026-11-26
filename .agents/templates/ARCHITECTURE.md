# Architecture

<!-- How the pieces fit. Read on demand, never loaded automatically, so it
     can be as long as it earns.

     Write it so someone can predict where a change goes before they open a
     file. If they still have to grep, this document has not done its job. -->

## The shape

<A table or a diagram in text. Every part, what it owns, and what it must
never do — that last column is the one that stops a change landing in the
wrong layer.>

| part | owns | must not |
|---|---|---|
| <name> | <its one responsibility> | <what belongs elsewhere> |

## The rules that hold it together

<The invariants. Things that are true everywhere, that a reader should assume
and a change must preserve. "All state lives in X." "Nothing below layer Y
knows about Z."

Each with what breaks if it is violated, because an invariant with no stated
cost is one somebody will trade away cheaply.>

## A request, end to end

<Follow one real path through the system, naming the files it touches in
order. One worked example teaches more than any description of the parts,
because it shows the seams.>

## Where a change goes

| if you are changing | it goes in | and you must also |
|---|---|---|
| <kind of change> | <where> | <what else to update> |

## Decisions and their reasons

<The choices that look wrong until you know why. Not a changelog — the two or
three places where the obvious approach was tried and abandoned, and what it
cost. This is the section that stops the same mistake being made twice.>
