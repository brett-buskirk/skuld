# Changelog

All notable changes to skuld are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-07-19

First release — the complete v1 task-tracker, one self-contained Bash script
(`set -uo pipefail`) built to the locked design decisions. Skuld is edda's sibling
(personal-vault-scoped, single-file, offline) and differs in exactly three ways, which
are the whole job: it stores **structured records**, runs a **state machine** over them,
and therefore needs **write safety** edda never did.

### Added

- **The storage seam & atomic writes** — all reads/writes go through `store_read` /
  `store_write`, the only code that knows the on-disk format. Every mutation rewrites the
  whole store to a temp file *beside* it (same filesystem → a true `mv` rename), so a
  crash or `Ctrl-C` mid-write leaves the previous store fully intact; the temp is cleaned
  on every failure/interrupt path. On disk the store is TAB-separated (readable,
  greppable); internally records use US (0x1f) between fields so a `read` split keeps
  empty columns. `enc`/`dec` escape `\t`, `\n`, and the backslash itself, so a name with
  a tab, a description with a newline, and a literal `C:\temp` all round-trip
  byte-identical on one physical line.
- **`init`** — scaffold the store (the ledger `tasks.tsv` + its `.trash/`) and a starter
  config. Idempotent, and never clobbers an existing ledger.
- **`add`** (alias `new`) — add a task: positional name; `-H/--high` or
  `--priority std|high`, `--due YYYY-MM-DD` (junk rejected, not stored), `-d/--desc`.
  Stamps `created` (ISO-8601 UTC) and starts `open`.
- **`list`** (alias `ls`) — open tasks by default, with a store-wide summary footer
  (`N open · N overdue · N done`). Filters: `--closed`, `--all`, `--overdue`,
  `--priority <level>` (`-H`). Sorting: `--sort id|due|priority|created` (+ `--reverse`),
  stable, no-due last. Overdue is a lexical date compare — no date math.
- **`show`** (alias `view`) — one task in full.
- **`close`** (alias `done`) / **`reopen`** — the binary `open ⇄ closed` state machine.
  `close` stamps `completed` automatically; `reopen` clears it. Both are gentle no-ops on
  a task already in the target state, so an earlier completion time is never overwritten.
- **`edit`** — flag-based field edits (`--name`/`--desc`/`--priority`/`--due`, `-H`); only
  the named fields change, and everything is validated before the store is touched. An
  empty `--due`/`--desc` clears; `--name` can't be emptied.
- **`rm`** (alias `del`) — soft-delete to `$SKULD_HOME/.trash/tasks.tsv` (the record is
  saved to the trash *before* it leaves the store, so a failed removal duplicates rather
  than loses). Confirms via `/dev/tty` (a pipe can't auto-confirm); `--force` skips it.
  There is no hard-delete path.
- **`--porcelain`** (on `list` and `show`) — the frozen, escape-free, TAB-separated column
  contract for scripting: `id·status·priority·created·due·completed·name·description`, one
  line per record, name/description backslash-encoded. No color, header, or footer.
- **IDs** are monotonic and never reused (`max(id)+1`), computed inside the same atomic
  write as the append.
- **Verb-first grammar** with a **closed dispatcher** and two ergonomic defaults: bare
  `skuld` → `list` open tasks, bare `skuld <id>` → `show` that task. Two-level help
  (`skuld help`, `skuld <cmd> help`), and a `NO_COLOR`/non-TTY-aware pipe-safe palette.
- **Store + config resolution** on the `env > config file > default` ladder
  (`$SKULD_HOME` > `$SKULD_CONFIG` file > `${XDG_DATA_HOME:-~/.local/share}/skuld`).
- `.github/workflows/shellcheck.yml` (`bash -n` + `shellcheck`) and
  `.github/workflows/test.yml` + `test/run.sh` — a throwaway-store harness (130 checks)
  covering the daily loop, the TSV-shearing and backslash round-trips, atomic-write
  survives a failed write with no temp litter, `next_id` monotonic/never-reused, ISO-due
  rejection, integer dispatch, the state machine, edit/rm, filters/sort, and the porcelain
  contract.
- README, ROADMAP, and this changelog.
