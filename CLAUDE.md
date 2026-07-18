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

## The script, to build

There is **no `skuld` script yet** — build it as one file, `set -uo pipefail`, mirroring edda/the
pack. Top→bottom: header comment (the Norn framing + usage synopsis) → `VERSION` → `SELF`/`HERE` →
**config/store resolution** (`SKULD_HOME` env > `${SKULD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/skuld/config}`
> `${XDG_DATA_HOME:-$HOME/.local/share}/skuld`) → palette (TTY + `NO_COLOR` aware) → helpers (`have` /
`is_help` / `note` / `store_read` / `store_write` / `next_id` / `fmt_task` / `is_overdue` / `age_short`)
→ `ensure_store` → the `cmd_*` functions (each guarded by `is_help`, while-loop `case` arg parsing) →
`help_*` → the `case` dispatcher, **with the empty→`list` and integer→`show` arms as the default
path**. Two-level help (`skuld help`, `skuld <cmd> help`). Respects `NO_COLOR` / non-TTY.

Surface (v1): **`add`/`new` · `list`/`ls` · `show`/`view` · `close`/`done` · `reopen` · `edit` · `rm`
· `init`**, plus `help` / `version`.
- `list` defaults to **open only**; `--closed`, `--all`, `--priority high`, `--overdue`, `--sort
  due|priority|created|id`, `--reverse`, `--porcelain`. Print a one-line summary footer (`3 open · 1
  overdue · 12 done`).
- `add`: positional name; `-d/--desc`, `-H/--high` or `--priority`, `--due YYYY-MM-DD`.
- `edit`: flag-based field edits (`--name`/`--desc`/`--priority`/`--due`) for scriptability; `$EDITOR`-
  on-record optional.
- `rm`: soft-delete to `.trash/`, confirm or `--force`.
ROADMAP (out for v1): tags/projects, recurring tasks, subtasks, reminders, `stats`, `cancelled` state,
natural-language dues, JSONL store.

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

- Every change must be `bash -n skuld` + `shellcheck skuld` clean. **Add the missing CI gate:** the
  scaffold wires AgentGate but not the `.github/workflows/shellcheck.yml` the rest of the pack runs on
  every push/PR — port it from `edda`/`vegtam` as the first infra PR (same gap edda had).
- **Test with a throwaway store** (`SKULD_HOME="$(mktemp -d)"`): add/list/close/reopen/edit + `rm`-
  lands-in-`.trash`; TSV round-trip with nasty fields; atomic-write leaves the old store intact on
  simulated failure; `next_id` monotonic and never-reused; overdue detection; `--porcelain` stability
  and zero escapes when piped; ISO-due rejection of junk input.
- Bump `VERSION`; keep `README` / `CHANGELOG` / `ROADMAP` in sync. After a PR merges, refresh Brett's
  installed copy: `install -m 0755 skuld ~/.local/bin/skuld`.

## Status

**Assumes the standard scaffold** — the same template as edda: MIT; AgentGate wired (`scope` →
warning, `secrets` + `dangerous_patterns` → error); doc suite stubbed; `.gitignore` covering
`.DS_Store` / `*.log`; **no `skuld` script yet, no `shellcheck.yml` yet,** ROADMAP milestone undefined,
README a one-liner. If the actual repo differs (an existing `CLAUDE.md`, a started script), reconcile
against reality first.

First milestone: **`init` + `add` + `list`** — scaffold the store, add a task, see your open tasks
(the smallest useful loop). Then `close`/`reopen`, then `show`/`edit`/`rm`, then the shellcheck gate.
**Once the script exists, replace "The script, to build" with a "The script, at a glance" section that
narrates the real file top→bottom**, the way vegtam's manual does.

## Reference

- `~/github-repos/edda/edda` — the sibling vault tool. Copy its skeleton wholesale: config ladder,
  palette, `have`-gated optionals, `.trash/` soft-delete, two-level help, `init`.
- `~/github-repos/vegtam/vegtam` — dispatcher / two-level help / the `confirm()` `/dev/tty` spine that
  `rm` borrows / the terse, lightly-wry voice.
- `~/github-repos/muninn/muninn` — the `env > config > default` ladder, and the `jq` patterns to lift
  **if** you ever take the JSONL upgrade.
