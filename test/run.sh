#!/usr/bin/env bash
# skuld test harness — a self-contained bash runner (no bats dependency), the way
# the pack is tested: throwaway stores (SKULD_HOME="$(mktemp -d)") exercising the
# surface end to end. Exits non-zero if any assertion fails.
#
#   bash test/run.sh            # run against ../skuld
#   SKULD_BIN=/path/to/skuld bash test/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKULD="${SKULD_BIN:-$HERE/../skuld}"
ESC=$'\x1b'

PASS=0; FAIL=0
declare -a TMPDIRS=()
cleanup(){ local d; for d in "${TMPDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

mkd(){ local d; d="$(mktemp -d)"; TMPDIRS+=("$d"); printf '%s' "$d"; }

# A fresh, isolated store + config for a test. Keeps SKULD_CONFIG out of ~/.config,
# and clears the XDG vars so the default-path resolution is tested deterministically.
fresh(){
  SKULD_HOME="$(mkd)"; export SKULD_HOME
  SKULD_CONFIG="$(mkd)/config"; export SKULD_CONFIG
  unset XDG_DATA_HOME XDG_CONFIG_HOME
}

pass(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; }
skip(){ printf '  skip %s%s\n' "$1" "${2:+  ($2)}"; }

assert_eq(){       if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi; }
assert_rc(){       if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected rc $2, got $3"; fi; }
assert_contains(){ case "$2" in *"$3"*) pass "$1";; *) fail "$1" "[$2] lacks [$3]";; esac; }
assert_missing(){  case "$2" in *"$3"*) fail "$1" "[$2] unexpectedly contains [$3]";; *) pass "$1";; esac; }
assert_file(){     if [ -f "$2" ]; then pass "$1"; else fail "$1" "no such file: $2"; fi; }
assert_no_esc(){   if printf '%s' "$2" | grep -q "$ESC"; then fail "$1" "output carries ANSI escapes"; else pass "$1"; fi; }

# ── init: scaffolds the store, .trash/, an empty ledger, and a starter config ────
t_init(){
  fresh
  "$SKULD" init >/dev/null
  { [ -d "$SKULD_HOME" ]            && pass "init creates the store dir"; } || fail "init creates the store dir"
  { [ -d "$SKULD_HOME/.trash" ]     && pass "init creates .trash/"; }       || fail "init creates .trash/"
  { [ -f "$SKULD_HOME/tasks.tsv" ]  && pass "init creates the ledger"; }    || fail "init creates the ledger"
  { [ -f "$SKULD_CONFIG" ]          && pass "init writes a config"; }       || fail "init writes a config"
  assert_contains "config points SKULD_HOME at the store" "$(cat "$SKULD_CONFIG")" "SKULD_HOME=\"$SKULD_HOME\""
}

# ── init is idempotent and NEVER clobbers an existing ledger ─────────────────────
t_init_idempotent(){
  fresh
  "$SKULD" init >/dev/null
  printf 'sentinel-task-data\n' > "$SKULD_HOME/tasks.tsv"   # stand in for real task data
  "$SKULD" init >/dev/null                                   # a second init must not truncate it
  assert_contains "re-init preserves an existing ledger" "$(cat "$SKULD_HOME/tasks.tsv")" "sentinel-task-data"
  # --force overwrites the config, but STILL must not touch the ledger
  "$SKULD" init --force >/dev/null
  assert_contains "init --force preserves the ledger" "$(cat "$SKULD_HOME/tasks.tsv")" "sentinel-task-data"
}

# ── pipe-safety: zero escapes under NO_COLOR / when piped ─────────────────────────
t_pipe_safety(){
  fresh; "$SKULD" init >/dev/null
  assert_no_esc "help piped: zero escapes"     "$("$SKULD" help)"
  assert_no_esc "init piped: zero escapes"     "$("$SKULD" init)"
  assert_no_esc "NO_COLOR help: zero escapes"  "$(NO_COLOR=1 "$SKULD" help)"
}

# ── config/store resolution ladder: env > file > default ─────────────────────────
t_ladder(){
  local envh fileh conf; envh="$(mkd)"; fileh="$(mkd)"; conf="$(mkd)/config"
  printf 'SKULD_HOME="%s"\n' "$fileh" > "$conf"

  # env beats the config file
  SKULD_HOME="$envh" SKULD_CONFIG="$conf" "$SKULD" init >/dev/null
  assert_file    "env store wins over config file"          "$envh/tasks.tsv"
  assert_missing "config-file store untouched when env set" "$(ls "$fileh")" "tasks.tsv"

  # file beats the default when env is unset
  env -u SKULD_HOME SKULD_CONFIG="$conf" "$SKULD" init >/dev/null
  assert_file "config-file store used when env unset" "$fileh/tasks.tsv"

  # default when neither env nor a config file is present
  local dh; dh="$(mkd)"
  local out; out="$(env -u SKULD_HOME SKULD_CONFIG="$conf.nope" XDG_DATA_HOME="$dh" "$SKULD" help)"
  assert_contains "default store = XDG_DATA_HOME/skuld" "$out" "$dh/skuld"
}

# ── dispatch: unknown verb errors cleanly (rc 1); help/version behave ────────────
t_dispatch(){
  fresh; "$SKULD" init >/dev/null
  local out rc
  out="$("$SKULD" definitely-not-a-verb 2>&1)"; rc=$?
  assert_rc       "unknown command is rc 1"        1 "$rc"
  assert_contains "unknown command errors cleanly" "$out" "no such command"
  assert_contains "version prints the version"     "$("$SKULD" version)" "skuld $("$SKULD" version | awk '{print $2}')"
  assert_contains "empty invocation shows help"    "$("$SKULD")" "the ledger of what you owe"
}

# ── run everything ───────────────────────────────────────────────────────────────
printf '\nskuld test harness — %s\n\n' "$SKULD"
[ -x "$SKULD" ] || { printf 'skuld not executable at %s\n' "$SKULD" >&2; exit 2; }

t_init
t_init_idempotent
t_pipe_safety
t_ladder
t_dispatch

printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
