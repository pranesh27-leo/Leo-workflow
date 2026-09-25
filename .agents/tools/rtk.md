# RTK — terminal output reduction

Filters shell output **structurally**: progress bars, repeated lines,
package-manager noise. Not a model deciding which lines you needed to see,
which is why it is on in every mode — the filtering is mechanical and cannot
quietly remove the one line that mattered.

Optional. Missing it is not an error — say so and carry on.

## Install

A single Rust binary with no dependencies. Native builds for macOS, Linux and
Windows.

    brew install rtk                 # macOS, Linux
    winget install rtk-ai.rtk        # Windows
    cargo install --git https://github.com/rtk-ai/rtk

Then:

    rtk init -g                      # installs the auto-rewrite hook

**You do not run this.** Show it to the developer and let them decide.

## The one thing that matters

RTK's hook rewrites shell commands. Exclude this harness's own reads from the
rewrite — the manifest, the plan and the task files are things you must see
in full, and a filtered read of a table you are about to fill in is a table
you will fill in wrong.

Nothing else here needs configuring. It is ambient: once the hook is in, it
is in effect, and there is nothing to announce or invoke.
