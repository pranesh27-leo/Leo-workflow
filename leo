#!/usr/bin/env bash
# leo — keep AI-written code reviewable.
#
# Four commands, one idea: the diff is not the record. The plan says what was
# asked for, the manifest says why each hunk exists, and both end up in the
# commit message so `git log` answers "why is this line here" years later,
# with no AI in the loop.
#
# Adding a command = dropping a file in core/cmd/. There is no registry.

# --------------------------------------------------------- not bash? ------
# Everything below this block is bash: BASH_SOURCE, arrays, local. Everything
# inside it is POSIX sh, because the shell reading it may not be bash.
#
# On Windows, `npm install -g leo-workflow` never runs the leo.ps1 next to this
# file. npm reads the shebang above, generates its own leo.cmd and leo.ps1 into
# the global bin directory, and those run the first thing named `bash` on PATH.
# When that is not bash -- a BusyBox applet from scoop, a portable toolchain,
# an App Execution Alias -- it reaches the first bash-only line and says
#
#     .../leo: line 15: syntax error: bad substitution
#
# naming a line that is correct bash, because the shell quoting it is not bash.
# No arrangement of package.json prevents this: npm picks the interpreter from
# the shebang and leo does not get a say. So leo asks who is running it, and
# if the answer is not bash, finds a bash and hands over.
#
# A candidate is accepted only if it sets BASH_VERSION, which is also what
# stops this from looping: whatever we exec can parse what follows.
if [ -z "${BASH_VERSION:-}" ]; then
  # `bash --version` is not the test -- BusyBox answers it too, with its own
  # version. Only bash sets BASH_VERSION, and asking for it is one expansion
  # every POSIX shell performs and only bash answers.
  _leo_is_bash() {
    [ -n "${1:-}" ] || return 1
    [ -x "$1" ] || return 1
    [ -n "$("$1" -c 'printf %s "${BASH_VERSION-}"' 2>/dev/null)" ]
  }

  # A Windows PATH is separated by ';' and its entries contain ':' (C:\...),
  # so the separator is decided once, here, rather than guessed per entry.
  case "$PATH" in
    *\;*) _leo_sep=';' ;;
    *)    _leo_sep=':' ;;
  esac

  # Candidates are generated one per line and consumed with `read -r`, never by
  # word splitting: these paths contain spaces ("C:/Program Files/Git/bin"),
  # and shells disagree about splitting anyway -- zsh does not split unquoted
  # expansions at all, so an IFS-based loop silently finds nothing there.
  #
  # LEO_BASH first: someone who sets it and is silently ignored spends a long
  # time wondering which bash ran. Then every bash on PATH rather than just the
  # first, because the first is the one that is not bash. Then the usual
  # Windows installs, because a machine can have Git for Windows and still not
  # have its bin directory on PATH.
  _leo_bash=$(
    {
      [ -n "${LEO_BASH:-}" ] && printf '%s\n' "$LEO_BASH"
      printf '%s' "${PATH:-}" | tr "$_leo_sep" '\n' 2>/dev/null | while IFS= read -r _d; do
        [ -n "$_d" ] && printf '%s\n%s\n' "$_d/bash" "$_d/bash.exe"
      done
      printf '%s\n' /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash
      # Git for Windows, found through git itself rather than guessed. This is
      # the one that matters in practice: a machine can have Git Bash and not
      # have it on PATH, while git.exe is on PATH because the installer puts
      # it there. git lives in <install>/cmd or <install>/mingw64/bin; bash is
      # in <install>/bin and <install>/usr/bin.
      _git=$(command -v git 2>/dev/null || true)
      if [ -n "$_git" ]; then
        _gitdir=$(dirname "$_git" 2>/dev/null || true)
        [ -n "$_gitdir" ] && printf '%s\n' \
          "$_gitdir/../bin/bash.exe" "$_gitdir/../usr/bin/bash.exe" \
          "$_gitdir/../../bin/bash.exe" "$_gitdir/../../usr/bin/bash.exe"
      fi
      [ -n "${PROGRAMFILES:-}" ] && printf '%s\n' "$PROGRAMFILES/Git/bin/bash.exe"
      [ -n "${LOCALAPPDATA:-}" ] && printf '%s\n' "$LOCALAPPDATA/Programs/Git/bin/bash.exe"
      printf '%s\n' \
        "C:/Program Files/Git/bin/bash.exe" \
        "C:/Program Files/Git/usr/bin/bash.exe" \
        "C:/Program Files (x86)/Git/bin/bash.exe" \
        "C:/msys64/usr/bin/bash.exe" \
        "C:/cygwin64/bin/bash.exe"
    } | while IFS= read -r _leo_c; do
      # Two entries are real bash and still the wrong answer, and both are
      # ordinarily on PATH ahead of Git Bash:
      #
      #   System32\bash.exe      launches WSL
      #   WindowsApps\bash.exe   an App Execution Alias for the same
      #
      # WSL's bash is bash, so the BASH_VERSION probe accepts it -- and then
      # leo is handed C:/Users/... which WSL cannot open, because it sees that
      # repository as /mnt/c/Users/... through a different git with a
      # different view of file modes and line endings. Skipped by path, before
      # being run: probing one of these can boot a distribution or open the
      # Store. `wsl leo` remains the way to ask for WSL on purpose.
      _leo_lc=$(printf '%s' "$_leo_c" | tr 'A-Z' 'a-z' | tr '\\' '/' 2>/dev/null)
      # The leading "(" is not decoration: this case sits inside $( ), where a
      # bare "pattern)" closes the command substitution early and the shell
      # reports a syntax error at the ";;" several lines later.
      case "$_leo_lc" in
        (*/system32/bash.exe|*/windowsapps/bash.exe) continue ;;
      esac
      if _leo_is_bash "$_leo_c"; then printf '%s' "$_leo_c"; break; fi
    done
  )

  if [ -z "$_leo_bash" ]; then
    # The advice leo.ps1 gives, for the reason it gives it: "bad substitution"
    # on a line of correct bash is not a clue anyone can act on.
    echo "ERR  leo needs bash, and the shell running it is not bash" >&2
    echo "     ran as: ${0:-leo}" >&2
    echo "" >&2
    echo "     Something on PATH is named bash but is not one; BusyBox and" >&2
    echo "     similar shims are the usual cause. Install Git for Windows," >&2
    echo "     which ships the bash leo wants:" >&2
    echo "         winget install --id Git.Git -e" >&2
    echo "" >&2
    echo "     Already have a bash? Point leo at it:" >&2
    echo "         LEO_BASH='C:/Program Files/Git/bin/bash.exe' leo ..." >&2
    exit 1
  fi

  exec "$_leo_bash" "$0" "$@"
fi

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
