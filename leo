#!/usr/bin/env bash
# leo — keep AI-written code reviewable.
#
# Four commands, one idea: the diff is not the record. The plan says what was
# asked for, the manifest says why each hunk exists, and both end up in the
# commit message so `git log` answers "why is this line here" years later,
# with no AI in the loop.
#
# Adding a command = dropping a file in core/cmd/. There is no registry.
set -euo pipefail

# Find our own install, following symlinks (so `ln -s .../bin/leo /usr/local/bin`
# works).
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _dir=$(cd -P "$(dirname "$_self")" && pwd)
  _self=$(readlink "$_self")
  case "$_self" in /*) ;; *) _self="$_dir/$_self" ;; esac
done
LEO_HOME=$(cd -P "$(dirname "$_self")" && pwd)
# The resolved path to this file. `leo commit` re-runs the checks by
# executing leo again, and in a bundle there is no $LEO_HOME/leo to run --
# the bundle is the whole install, so it re-execs itself.
LEO_SELF="$_self"
export LEO_HOME LEO_SELF

. "$LEO_HOME/core/lib.sh"

cmd="${1:-help}"
[ $# -gt 0 ] && shift

case "$cmd" in
  -h|--help)  cmd=help ;;
  --version)  echo "leo $(leo_version)"; exit 0 ;;
esac

_file="$LEO_HOME/core/cmd/$cmd.sh"
[ -f "$_file" ] || die "unknown command: $cmd  (try: leo help)"

. "$_file"
