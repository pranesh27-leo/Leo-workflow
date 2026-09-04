# Headroom — context compression

Semantic compression at the API boundary. Every mode that exists to preserve
detail turns it off: during debugging, learning and exploration the line that
matters is routinely the line that looks like noise, and this is a model
deciding which lines those were.

On in `coding` and `review`. Off in `debugging`, `learning` and `exploration`.

## It installs Serena behind your back

```sh
headroom wrap claude
```

installs Serena itself, at **user scope** in `~/.claude.json`, and leaves it
there until you unwrap. If you have already configured Serena, you now have it
twice. Check `~/.claude.json` before and after, or configure Serena once and
leave headroom unwrapped.

## The overlap with RTK

Both reduce what reaches you, and `leo session` reports the pair as a conflict
whenever both are on. RTK filters shell output structurally; headroom then
compresses a buffer RTK has already made dense. The second pass returns less
than the first, and it adds a failure mode the first does not have.

That is a reason to think about it, not a rule. The measured cost of keeping
both is small. The reason to drop one is the failure mode during detail work —
which is exactly what the mode policy already does for you.

## Weight

A Python toolchain, ONNX Runtime, and a model downloaded on first use. It is
the heaviest thing on leo's list by a wide margin.
