#!/usr/bin/env bash
# desc: install a tool this session declares
# usage: leo install              what is installed, and what is not
#        leo install <name>       install one
#        leo install --all        install everything this session declares
#
# THIS COMMAND CHANGES YOUR MACHINE. Almost everything it runs is somebody
# else's installer, fetched over the network, and leo has not audited it. So it
# behaves like `leo commit` does: it prints the exact command, it refuses
# without a human at a terminal, and it never runs as a side effect of anything.
#
# Nothing else in leo installs. `leo session` declares, `leo check` verifies,
# and both work on a machine with none of these tools present. That property is
# what makes an optional dependency actually optional, and this command is
# deliberately the only place it can be spent.

need_repo

_all=0; _want=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) _all=1; shift ;;
    -*)    die "unknown option: $1" ;;
    *)     _want="$1"; shift ;;
  esac
done

# state <cap> — one word for where a capability stands, so the listing and the
# install path agree by construction rather than by two people remembering.
state() {
  _rc=0; cap_present "$1" || _rc=$?
  case "$_rc" in
    0) printf 'installed' ;;
    2) printf 'no adapter' ;;
    *) command -v "${1}_install" >/dev/null 2>&1 \
         && printf 'missing' || printf 'manual' ;;
  esac
}

# one <cap> — show what would run, ask, run it, then check it worked.
one() {
  _cap="$1"
  _st=$(state "$_cap")
  case "$_st" in
    installed)   ok "$_cap is already installed"; return 0 ;;
    "no adapter") warn "$_cap has no adapter — leo cannot install it"; return 0 ;;
    manual)
      warn "$_cap has no installer in its adapter — do it by hand:"
      cap_call "$_cap" hint | sed 's/^/      /' >&2
      return 0 ;;
  esac

  _cmds=$(cap_call "$_cap" install)
  [ -n "$_cmds" ] || { warn "$_cap declares no install command"; return 0; }

  head_ "install $_cap"
  info "  leo will run this. It is not leo's code, and leo has not audited it:"
  echo >&2
  printf '%s\n' "$_cmds" | sed 's/^/      /' >&2
  echo >&2

  if [ -z "${LEO_YES:-}" ]; then
    printf 'run it? [y/N] ' >&2
    read -r _a || _a=n
    _a=$(printf '%s' "$_a" | tr -d '\r')
    case "$_a" in [yY]|[yY][eE][sS]) ;; *) info "skipped $_cap"; return 0 ;; esac
  fi

  # `sh -e` so a multi-step installer stops at the first failure instead of
  # carrying on and reporting success from its last line.
  if sh -e -c "$_cmds"; then
    if cap_present "$_cap"; then
      ok "$_cap installed"
      cap_call "$_cap" advice | sed 's/^/      /' >&2
    else
      # The common cause is a new binary in a directory this shell has not
      # looked at yet, which is a shell problem and not a failure to install.
      warn "$_cap ran without error but is still not on PATH — open a new shell"
    fi
  else
    err "$_cap install failed"
    info "  by hand:"
    cap_call "$_cap" hint | sed 's/^/      /' >&2
    return 1
  fi
}

# --- listing --------------------------------------------------------------
if [ "$_all" -eq 0 ] && [ -z "$_want" ]; then
  head_ "leo install"
  for _c in $CAPS; do
    _d=$(cap_state "$_c"); _d="${_d:-off}"
    printf '  %-13s %-11s %s\n' "$_c" "$(state "$_c")" \
      "$(printf '%s' "$_d" | tr 'a-z' 'A-Z')" >&2
  done
  echo >&2
  dim "  leo install <name>     install one"
  dim "  leo install --all      install everything this session declares"
  exit 0
fi

# Past this point leo is going to change the machine, so the same rule as
# `leo commit`: somebody has to be here to answer for it.
if [ ! -t 0 ] && [ -z "${LEO_YES:-}" ]; then
  err "leo install needs a human at a terminal"
  info ""
  info "If you are an agent: do not install anything. Show the developer"
  info "\`leo install\` and let them decide what goes on their machine."
  info ""
  info "If you are a human whose shell has no tty: LEO_YES=1 leo install ..."
  exit 2
fi

if [ -n "$_want" ]; then
  printf '%s\n' $CAPS | grep -qx "$_want" \
    || die "unknown capability: $_want  (leo install — to list them)"
  one "$_want"
  exit 0
fi

# --all: only what this session actually declares. Installing a tool the mode
# turns off would be leo deciding something the mode already decided.
[ -n "$MODE" ] || die "no session — start one: leo session --mode coding"
_n=0
for _c in $CAPS; do
  [ "$(cap_state "$_c")" = "on" ] || continue
  [ "$(state "$_c")" = "missing" ] || continue
  one "$_c" || true
  _n=$((_n + 1))
done
[ "$_n" -eq 0 ] && ok "everything this session declares is already installed"
