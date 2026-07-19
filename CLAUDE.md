# CLAUDE.md — Skuld

Working manual for a Claude Code agent editing **this** repo. Two parent files auto-load above it via
the directory walk and own the universal rules — this file does **not** restate them:

- **`/etc/claude-code/CLAUDE.md`** (machine policy) — the chain of command (branch → PR → **Brett
  merges**; never self-merge, never commit to `main`), signed commits, the safety floors, brand
  positioning, NIST AI RMF.
- **`~/github-repos/CLAUDE.md`** (estate manual) — issue/PR wiring (assignee `brett-buskirk`, labels,
  milestone, Estate board **#17**), the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  trailer, the AgentGate `dangerous_patterns`-fires-in-prose quirk, the `brett-buskirk`-must-be-the-
  active-gh-account gotcha, the pack, and the estate memory.

Everything below is Skuld-specific.

## What Skuld is

`skuld` is a single-file CLI **task tracker** — a checklist over a small, structured store. Named for
the Norn who governs the future (her name is cognate with "shall"/"should" and connotes *debt,
obligation, that-which-must-become*), it is the ledger of what you owe your future self. It is the
**fate-tracker to edda's codex**: edda records what *was*, skuld records what *shall be*.

Architecturally it is edda's sibling — **personal-vault-scoped, single-file bash, fully offline** —
and it inherits edda's whole skeleton (config ladder, palette, `have`-gated optionals, verb-first
dispatcher, two-level help, `init`, soft-delete-to-`.trash/`, shellcheck gate, doc suite). Copy that
shape; **do not re-derive it.** Skuld differs from edda in exactly three ways, and they are the whole
job: it stores **structured records**, it runs a **state machine** over them, and it therefore needs
**write safety** edda never did.

## The governing design decisions — never violate

1. **Atomic writes — the marquee rule.** Every mutation rewrites the whole store, so **write a temp
   file in the store's own directory and `mv` it into place.** Never edit in place. A `Ctrl-C` or crash
   mid-write must leave the *previous* store fully intact — never a half-applied rewrite with the tail
   of the task list truncated off. `mktemp` **beside** the store (same filesystem, or `mv` isn't
   atomic — `/tmp` may be a different mount), and trap-clean the temp on failure. This is skuld's #1
   correctness invariant; treat any in-place `>>`/`sed -i` on the store as a bug.
2. **The store is sacred and bounded.** Every write lands **inside `$SKULD_HOME`** and nowhere else.
   Offline always — no `gh`, no `curl`, no network. `rm` **soft-deletes to `$SKULD_HOME/.trash/`**;
   there is no hard-delete path.
3. **Storage lives behind one seam.** All reads/writes go through `store_read` / `store_write` — the
   rest of the tool never sees the file format. That keeps the documented TSV→JSONL upgrade a
   one-function change instead of a rewrite.
4. **Dispatch is closed.** Verbs are a fixed set. The **only** non-verb arms are: **empty invocation →
   `list` open tasks**, and **a bare integer → `show` that task**. Nothing else free-form reaches the
   first dispatch position.

## The locked design (build to these)

- **Grammar — verb-first, with two ergonomic defaults.**
  `skuld add`, `list`, `show`, `close`, `reopen`, `edit`, `rm`, `init`. Then: bare **`skuld` → `list`**
  open tasks (the daily driver — type five letters, see what you owe); **`skuld <id>` → `show`** that
  task (an integer is unambiguously not a verb).
- **Store — single tab-separated file** at `$SKULD_HOME/tasks.tsv`, one task per line, fixed columns:
  `id ⇥ status ⇥ priority ⇥ created ⇥ due ⇥ completed ⇥ name ⇥ description`.
  Zero external deps — filter/sort with `awk`/`sort` on columns. **Sanitize on write:** tabs and
  newlines in `name`/`description` shear the columns, so encode them (`\t`→`\\t`, `\n`→`\\n`) in
  `store_write` and decode in `store_read`. JSONL + `jq` is the documented upgrade path if tasks later
  grow nested data (subtasks, tags, history) — hence the `store_*` seam.
- **IDs — monotonic integers, never reused.** `next_id = max(id)+1`; a deleted `4` never returns.
  Compute `next_id` inside the same atomic write section as the append so two quick `add`s can't
  collide. Validate that any id argument is actually an integer before dispatch.
- **State — `open ⇄ closed`, binary.** `close`/`done` stamps `completed` (auto); `reopen` clears it and
  flips back to `open`. That's the whole machine. A `cancelled` third state is roadmap, not v1.
- **Priority — `standard` (default) / `high`.** `-H/--high` is the "flag for higher"; `--priority
  <level>` is the explicit form. Give priority an explicit numeric rank so `--sort priority` is
  deterministic.
- **Dates — ISO-8601, portable.** `created`/`completed` are auto `date -u +%FT%TZ` (works on GNU *and*
  BSD). `--due` accepts **only `YYYY-MM-DD`** in v1 — reject anything else with a clear error, don't
  silently store junk. Natural-language dues (`tomorrow`, `+3d`) need `date -d` (GNU-only; BSD uses
  `-v`), so gate them behind a `have gdate` check as a **roadmap** nicety.
- **Machine-readable output — design the contract now.** A `--porcelain` mode on `list`/`show` emits
  stable, escape-free, script-parseable lines (fixed column order that later versions don't reorder).
  This is what lets skuld compose into other automation. The fancy filtering can wait; the stable
  output contract cannot.

## The script, at a glance

One file, `skuld`, `set -uo pipefail`. Deps: **`bash` + coreutils only** — fully offline. Read
top→bottom:

- **Header** (the Norn framing + usage synopsis) → `VERSION` → the **config/store ladder**
  (`SKULD_HOME` env > `$SKULD_CONFIG` file > `${XDG_DATA_HOME:-~/.local/share}/skuld`), which also
  fixes `STORE` (`tasks.tsv`), `TRASH` (`.trash/`), and `US` (the 0x1f internal field separator) →
  the frozen column-order comment → the **palette** (TTY + `NO_COLOR` aware).
- **Small helpers:** `is_help` · `note` · `is_int` · `now_iso`/`today` (portable `date -u`) ·
  `valid_due` (strict `YYYY-MM-DD` regex) · `is_overdue` (lexical `due < today`, no date math).
- **The storage seam — the ONLY code that knows the on-disk format:** `enc`/`dec` (escape/unescape
  `\t`, `\n`, `\\`; `dec` is a single left-to-right pass) → `store_read` (TAB→US, skips blanks) →
  `store_write` (**atomic**: US→TAB into a temp *beside* the store, then `mv`; temp cleaned on every
  failure/interrupt) → `next_id` (max+1, never reused) → `build_record` → `find_task` / `field` →
  `set_task_state` (close/reopen's mutator) / `replace_task` (edit's mutator — passes the new record
  via **`ENVIRON`, never `awk -v`**, so its escapes survive) → `ensure_store`.
- **The `cmd_*` functions** (each guarded by `is_help`, then `case` arg parsing): `cmd_init` →
  `cmd_add` → the list stack (`read_totals` · `filter_key` · `list_label` · `cmd_list` · `fmt_row`) →
  `cmd_show` → `cmd_close`/`cmd_reopen` → `cmd_edit` → `confirm` (the `/dev/tty` spine) → `cmd_rm`.
- **`help_*`** (per-command detail) → **`cmd_help`** (the menu) → the **`case` dispatcher** — closed,
  with the empty→`list` and integer→`show` arms as the default path.

Surface (v1, shipped in v1.0.0): **`add`/`new` · `list`/`ls` · `show`/`view` · `close`/`done` ·
`reopen` · `edit` · `rm`/`del` · `init`**, plus `help` / `version`. `list` defaults to open-only with
filters (`--closed`/`--all`/`--overdue`/`--priority`), `--sort id|due|priority|created`, `--reverse`,
and `--porcelain`; its footer (`N open · N overdue · N done`) is always store-wide. Two-level help
(`skuld help`, `skuld <cmd> help`). Respects `NO_COLOR` / non-TTY.

The record's 8 fixed columns — **frozen**, later versions append and never reorder:
`id ⇥ status ⇥ priority ⇥ created ⇥ due ⇥ completed ⇥ name ⇥ description` (TAB-separated on disk,
US-separated internally, `name`/`description` backslash-encoded). `--porcelain` emits exactly this.

Note the file mirrors edda's shape but does **not** carry every helper the pack template lists: there's
no `SELF`/`HERE`, `have`, `fmt_task`, or `age_short` (unused → they'd trip `SC2034`); the list row
formatter is `fmt_row`. What's next lives in `ROADMAP.md`.

## Gotchas (write a test for each)

- **TSV shearing.** A tab or newline in `name`/`description` destroys the column layout. Round-trip
  test: a name containing a tab and a description containing a newline must survive write→read
  byte-identical. This is why `store_*` owns encode/decode — nothing else touches raw lines.
- **Atomicity is filesystem-dependent.** `mktemp` in the store dir, not `/tmp` — a cross-mount `mv`
  falls back to copy+unlink and isn't atomic. Simulate a mid-write failure and assert the old store is
  untouched and no temp litter remains.
- **`next_id` races.** Computed outside the atomic section, two fast `add`s dup an id. Compute-and-
  append in one guarded step; a `flock` on the store is cheap extra insurance (roadmap-optional).
- **Integer dispatch validation.** `skuld 4` → show; `skuld 4x` → clean error, not a crash. Validate
  the id is a pure integer, and that `show`/`close`/etc. on a nonexistent id fail gracefully.
- **Overdue comparison needs no date math.** ISO `YYYY-MM-DD` compares lexically, so `[[ "$due" <
  "$today" ]]` is correct and portable — lean on it rather than shelling out to `date` arithmetic.
- **Porcelain must stay dumb.** The human `list` gets color, alignment, and overdue markers; porcelain
  gets none — same `NO_COLOR`/non-TTY discipline as edda, plus a frozen column contract. Test: piped
  output has **zero escape bytes** and a stable field order.
- **shellcheck `SC2059`** (vars in printf format) is disabled file-level on purpose, matching the pack;
  otherwise stay shellcheck-clean.

## Editing & shipping

- Every change must be `bash -n skuld` + `shellcheck skuld` clean, and keep `test/run.sh` green. CI
  runs all three on every push/PR: `.github/workflows/shellcheck.yml` (`bash -n` + `shellcheck`) and
  `.github/workflows/test.yml` (`bash test/run.sh`), alongside AgentGate.
- **Test with a throwaway store** (`SKULD_HOME="$(mktemp -d)"`): add/list/close/reopen/edit + `rm`-
  lands-in-`.trash`; TSV round-trip with nasty fields; atomic-write leaves the old store intact on
  simulated failure; `next_id` monotonic and never-reused; overdue detection; `--porcelain` stability
  and zero escapes when piped; ISO-due rejection of junk input.
- Bump `VERSION`; keep `README` / `CHANGELOG` / `ROADMAP` in sync. After a PR merges, refresh Brett's
  installed copy: `install -m 0755 skuld ~/.local/bin/skuld`.

## Status

**v1.0.0 — shipped.** The full v1 surface is built, tested (130 checks), and CI-gated
(`shellcheck` + `test` + AgentGate). The whole locked design is in: structured records behind the
`store_read`/`store_write` seam, atomic writes, the `open ⇄ closed` state machine, `.trash/`
soft-delete, filters/sort, and the frozen `--porcelain` contract. It was built as a stack of focused
PRs (skeleton+init → add/list/show → close/reopen → edit/rm → filters/porcelain → this docs pass),
plus a small CI PR that added `test.yml`. See `CHANGELOG.md` / `ROADMAP.md` for the record and what's
next; `## The script, at a glance` above narrates the real file.

For work from here: keep every change `bash -n` + `shellcheck` + `test/run.sh` clean, bump `VERSION`,
keep the docs in sync, and after a PR merges refresh Brett's installed copy
(`install -m 0755 skuld ~/.local/bin/skuld`).

## Reference

- `~/github-repos/edda/edda` — the sibling vault tool. Copy its skeleton wholesale: config ladder,
  palette, `have`-gated optionals, `.trash/` soft-delete, two-level help, `init`.
- `~/github-repos/vegtam/vegtam` — dispatcher / two-level help / the `confirm()` `/dev/tty` spine that
  `rm` borrows / the terse, lightly-wry voice.
- `~/github-repos/muninn/muninn` — the `env > config > default` ladder, and the `jq` patterns to lift
  **if** you ever take the JSONL upgrade.
