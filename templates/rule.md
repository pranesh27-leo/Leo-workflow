# <one-line rule, stated as a MUST or MUST NOT>

MUST NOT: <the mistake, precisely enough that the check below is obvious>

Learned from: <the bug, PR or incident that made this worth a file>

## Verify

Exit 0 when the rule holds, non-zero when it is violated. `leo check` runs this
from the repository root. Keep it fast, and keep it something a human can paste
into a terminal.

```sh
! grep -rn 'return err$' --include='*.go' ./internal
```
