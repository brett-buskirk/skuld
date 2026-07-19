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
  "$SKULD" add -H --due 2000-01-01 "piped task" >/dev/null   # exercises the high + overdue color paths
  assert_no_esc "help piped: zero escapes"     "$("$SKULD" help)"
  assert_no_esc "init piped: zero escapes"     "$("$SKULD" init)"
  assert_no_esc "list piped: zero escapes"     "$("$SKULD" list)"
  assert_no_esc "show piped: zero escapes"     "$("$SKULD" show 1)"
  assert_no_esc "NO_COLOR list: zero escapes"  "$(NO_COLOR=1 "$SKULD" list)"
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
  assert_contains "empty invocation lists open tasks" "$("$SKULD")" "open tasks"
}

# ── add / list / show: the daily loop ────────────────────────────────────────────
t_add_list_show(){
  fresh; "$SKULD" init >/dev/null
  "$SKULD" add -H --due 2000-01-01 -d "the details" "Important thing" >/dev/null
  local st; st="$(cat "$SKULD_HOME/tasks.tsv")"
  assert_contains "add writes a record"        "$st" "Important thing"
  assert_contains "add stamps status open"     "$st" $'\topen\t'
  assert_contains "add stores high priority"   "$st" "high"
  assert_contains "add stores the due date"    "$st" "2000-01-01"

  local ls; ls="$("$SKULD" list)"
  assert_contains "list shows the task name"   "$ls" "Important thing"
  assert_contains "list flags an overdue due"  "$ls" "overdue"
  assert_contains "list footer counts open"    "$ls" "1 open"
  assert_contains "list footer counts overdue" "$ls" "1 overdue"

  local sh; sh="$("$SKULD" show 1)"
  assert_contains "show displays the description" "$sh" "the details"
  assert_contains "show displays created"         "$sh" "created"
  assert_contains "show marks high priority"      "$sh" "priority   high"
}

# ── list defaults to open only, with a working footer ────────────────────────────
t_list_empty_and_counts(){
  fresh; "$SKULD" init >/dev/null
  local ls; ls="$("$SKULD" list)"
  assert_contains "empty list says so"      "$ls" "no open tasks"
  assert_contains "empty list footer 0/0/0" "$ls" "0 open · 0 overdue · 0 done"
}

# ── TSV shearing: a tab in the name + a newline in the desc round-trip exactly ────
t_tsv_roundtrip(){
  fresh; "$SKULD" init >/dev/null
  local nm=$'col1\tcol2' dsc=$'line one\nline two'
  "$SKULD" add --desc "$dsc" "$nm" >/dev/null
  # the record MUST stay on one physical line (the newline is encoded, not literal)
  assert_eq "embedded newline keeps the record on one line" "1" "$(grep -c '' "$SKULD_HOME/tasks.tsv")"
  # …and both fields must survive write→read byte-identical
  local sh; sh="$("$SKULD" show 1)"
  assert_contains "name round-trips with its tab"            "$sh" "$nm"
  assert_contains "description round-trips with its newline" "$sh" "$dsc"
}

# ── a literal backslash (a Windows path) round-trips (escape-the-escape) ──────────
t_backslash_roundtrip(){
  fresh; "$SKULD" init >/dev/null
  "$SKULD" add 'C:\temp\notes' >/dev/null
  assert_contains "backslash stored escaped" "$(cat "$SKULD_HOME/tasks.tsv")" 'C:\\temp\\notes'
  assert_contains "backslash round-trips"    "$("$SKULD" show 1)" 'C:\temp\notes'
}

# ── next_id: monotonic, max+1, never reused ──────────────────────────────────────
t_next_id(){
  fresh; "$SKULD" init >/dev/null
  "$SKULD" add one >/dev/null; "$SKULD" add two >/dev/null; "$SKULD" add three >/dev/null
  # remove #2 directly (proper rm lands in a later PR) to open a gap in the id space
  grep -v "^2$(printf '\t')" "$SKULD_HOME/tasks.tsv" > "$SKULD_HOME/tasks.tsv.tmp"
  mv "$SKULD_HOME/tasks.tsv.tmp" "$SKULD_HOME/tasks.tsv"
  "$SKULD" add four >/dev/null                         # max id was 3 → must be 4, not reuse 2
  assert_contains "next_id is max+1 (not a count)" "$("$SKULD" show 4)" "#4"
  local rc; "$SKULD" show 2 >/dev/null 2>&1; rc=$?
  assert_rc "a removed id is never reused" 1 "$rc"
}

# ── --due validation: only YYYY-MM-DD; junk is rejected, never stored ─────────────
t_due_validation(){
  fresh; "$SKULD" init >/dev/null
  local rc
  "$SKULD" add --due 2026-07-20 ok    >/dev/null 2>&1; rc=$?; assert_rc "valid ISO due accepted"        0 "$rc"
  "$SKULD" add --due tomorrow   nl    >/dev/null 2>&1; rc=$?; assert_rc "natural-language due rejected" 1 "$rc"
  "$SKULD" add --due 2026-13-40 bad   >/dev/null 2>&1; rc=$?; assert_rc "out-of-range date rejected"    1 "$rc"
  "$SKULD" add --due 07/20/2026 usfmt >/dev/null 2>&1; rc=$?; assert_rc "US format rejected"           1 "$rc"
  assert_eq "only the valid task reached the store" "1" "$(grep -c '' "$SKULD_HOME/tasks.tsv")"
}

# ── integer dispatch: bare int → show; a non-int non-verb is a clean error ────────
t_int_dispatch(){
  fresh; "$SKULD" init >/dev/null
  "$SKULD" add "a task" >/dev/null
  assert_contains "bare integer shows that task" "$("$SKULD" 1)" "a task"
  local out rc
  out="$("$SKULD" 4x 2>&1)"; rc=$?
  assert_rc       "non-integer non-verb is rc 1"       1 "$rc"
  assert_contains "non-integer non-verb errors clean"  "$out" "no such command"
  out="$("$SKULD" 99 2>&1)"; rc=$?
  assert_rc       "bare int for a missing task is rc 1" 1 "$rc"
  assert_contains "missing task errors cleanly"         "$out" "no task"
}

# ── atomic write: a failed mutation leaves the old store intact + no temp litter ──
t_atomic(){
  fresh; "$SKULD" init >/dev/null
  "$SKULD" add first  >/dev/null
  "$SKULD" add second >/dev/null
  if [ "$(id -u)" = 0 ]; then
    skip "failed write leaves the old store intact" "running as root (perms don't bite)"
    skip "no temp litter after a failed write"      "running as root"
    return
  fi
  local before; before="$(cat "$SKULD_HOME/tasks.tsv")"
  chmod 500 "$SKULD_HOME"                              # store dir unwritable → mktemp fails
  local rc; "$SKULD" add "should fail" >/dev/null 2>&1; rc=$?
  chmod 700 "$SKULD_HOME"                              # restore so cleanup can remove it
  assert_rc "failed write is rc 1"                     1 "$rc"
  assert_eq "failed write leaves the old store intact" "$before" "$(cat "$SKULD_HOME/tasks.tsv")"
  assert_eq "no temp litter after a failed write"      "" "$(find "$SKULD_HOME" -name '.skuld-tmp.*')"
}

# ── run everything ───────────────────────────────────────────────────────────────
printf '\nskuld test harness — %s\n\n' "$SKULD"
[ -x "$SKULD" ] || { printf 'skuld not executable at %s\n' "$SKULD" >&2; exit 2; }

t_init
t_init_idempotent
t_add_list_show
t_list_empty_and_counts
t_tsv_roundtrip
t_backslash_roundtrip
t_next_id
t_due_validation
t_int_dispatch
t_atomic
t_pipe_safety
t_ladder
t_dispatch

printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
