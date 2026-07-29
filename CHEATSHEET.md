# skuld cheat sheet

Quick reference for every command, option, and behavior. `skuld` is a single self-contained Bash
script — a **task-tracker** over one small structured file (`tasks.tsv`), **fully offline**. It's the
ledger of what you owe your future self.

For the narrative version see the [README](README.md); for per-command detail in the terminal, run
`skuld <command> help`.

---

## At a glance

| Command | Aliases | What it does | Options |
|---------|---------|--------------|---------|
| [`add`](#add) | `new` | Add a task | `-H`/`--high`, `--priority`, `--due`, `-d`/`--desc` |
| [`list`](#list) | `ls` | List tasks — open by default | `--closed`, `--all`/`-a`, `--overdue`, `--priority`, `--sort`, `-r`/`--reverse`, `--porcelain` |
| [`show`](#show) | `view` | Show one task in full | `--porcelain` |
| [`close`](#close) | `done` | Mark a task done | |
| [`reopen`](#reopen) | | Reopen a closed task | |
| [`edit`](#edit) | | Change a task's fields | `--name`, `-d`/`--desc`, `--priority`/`-H`, `--due` |
| [`rm`](#rm) | `del` | Soft-delete a task to `.trash/` | `-f`/`--force` |
| [`init`](#init) | | Scaffold the store + a starter config | `-f`/`--force` |
| [*(nothing)*](#the-bareword-fast-paths) | | *(no verb)* list open tasks | |
| [`<id>`](#the-bareword-fast-paths) | | *(no verb)* show that task | |
| [`help`](#help--version) | `-h`, `--help` | The command menu | |
| `version` | `-V`, `--version` | Print the version | |

- **Write** commands (`add` `edit` `close` `reopen` `rm`) create or change tasks — and `rm` only ever
  *soft-deletes* (to `.trash/`). **Read** commands (`list` `show`) never change anything.
- The grammar is **verb-first**, with two ergonomic defaults: a bare `skuld` lists your open tasks,
  and `skuld <id>` shows that task (an integer is unambiguously not a verb). Nothing else free-form
  reaches the dispatcher — verbs always win the first position.
- An unknown word that isn't a verb and isn't an integer gives a clean error plus the menu (exit 1).

---

## Requirements & global behavior

- **Requires only** `bash` + coreutils (`awk`, `sort`, `tr`, `mktemp`, `date`) — nothing else to
  install. Timestamps use `date -u +%FT%TZ`, which is portable across **GNU and BSD/macOS**, so skuld
  runs the same everywhere.
- **Offline, always.** No `gh`, no `curl`, no network calls of any kind.
- **Atomic writes.** Every mutation rewrites the whole store to a temp file *beside* it, then `mv`s it
  into place — a crash or `Ctrl-C` mid-write leaves the previous store fully intact.
- **`NO_COLOR`** — set it (`NO_COLOR=1 skuld …`) to disable color. Output is also automatically plain
  when piped or redirected (not a TTY). `list`/`show` emit **zero escape codes** when piped, and
  `--porcelain` is the stable, escape-free contract to script against.
- **Two-level help** — `skuld help` for the menu, `skuld <command> help` (or `-h`/`--help`) for one
  command.
- **Exit codes** — `0` on success; `1` on error (no store, a missing task, a non-integer id, an
  invalid `--due`, an empty `--name`, an unknown command, or a usage error). Gentle no-ops
  (re-closing a closed task, reopening an open one) exit `0`, and an `rm` that aborts at the
  confirmation prompt also exits `0` (nothing was removed).

### The store, and how it's found

Every task lives in one tab-separated file — the **ledger**, `tasks.tsv`, inside the store directory —
resolved with the same ladder every command uses, **env > config file > default**:

| Priority | Source | Value |
|----------|--------|-------|
| 1 | `SKULD_HOME` in the environment | whatever you export |
| 2 | `SKULD_HOME` in the config file | `$SKULD_CONFIG`, default `${XDG_CONFIG_HOME:-~/.config}/skuld/config` (a sourced shell file) |
| 3 | the default | `${XDG_DATA_HOME:-~/.local/share}/skuld` |

Point `SKULD_HOME` at a synced or version-controlled directory and the ledger travels with you. The
store holds the ledger `tasks.tsv` and a `.trash/` (where `rm` soft-deletes to).

### Environment variables

| Variable | Effect |
|----------|--------|
| `SKULD_HOME` | The store directory (highest priority). |
| `SKULD_CONFIG` | Path to the config file (default `${XDG_CONFIG_HOME:-~/.config}/skuld/config`). |
| `XDG_CONFIG_HOME` / `XDG_DATA_HOME` | Feed the config-path and default-store fallbacks. |
| `NO_COLOR` | Any value disables color. |

### The store format

The ledger is a single tab-separated file at `$SKULD_HOME/tasks.tsv`, one task per line, with a fixed
column order. Zero external dependencies — you can `grep`, `awk`, and back it up yourself.

```
id ⇥ status ⇥ priority ⇥ created ⇥ due ⇥ completed ⇥ name ⇥ description
```

| Column | Values |
|--------|--------|
| `id` | Monotonic integer, **never reused** (`max(id)+1`, so a deleted `#4` never returns). |
| `status` | `open` or `closed`. |
| `priority` | `standard` or `high`. |
| `created` | ISO-8601 UTC, auto (`2026-07-19T14:00:00Z`). |
| `due` | `YYYY-MM-DD`, or empty. |
| `completed` | ISO-8601 UTC when closed, else empty. |
| `name` | The task name — `\t`, `\n`, and `\` are backslash-encoded, so a tab or newline never shears the columns and each record stays on one physical line. |
| `description` | Optional longer text, encoded the same way. |

The column order is **frozen** — later versions only ever append, never reorder. This is exactly what
`--porcelain` emits (see [Scripting](#scripting-with---porcelain)).

---

## Write

### `add`

Add a task (alias: `new`). The **name** is the positional text; everything else is a flag. A task
starts `open`, `standard` priority, no due date, with `created` stamped automatically.

```sh
skuld add "Buy milk"                                      # open, standard, no due
skuld add -H "Call the plumber"                           # -H = high priority
skuld add --due 2026-08-01 -d "draft + review" "Ship it"  # due + a description
skuld new "Renew passport"                                # alias
```

| Option | Effect |
|--------|--------|
| `-H`, `--high` | High priority (the flag for higher). |
| `--priority <level>` | Set priority explicitly: `standard` \| `high`. |
| `--due <YYYY-MM-DD>` | A due date. v1 accepts **only** that exact ISO format. |
| `-d`, `--desc <text>` | A longer description. |
| `--` | End-of-options: everything after it is the literal name (for a name that starts with a dash). |

Flags interleave with the name words. Refuses (rc 1) on an empty name, or a `--due` that isn't a
real-looking `YYYY-MM-DD` (`tomorrow`, `07/20/2026`, `2026-13-40` are all rejected, not stored). The
store is rewritten atomically.

### `edit`

Change a task's fields — only the ones you name; `id`, `status`, and the timestamps are left alone
(use `close`/`reopen` for status). Flag-based, so it scripts cleanly.

```sh
skuld edit 5 --name "Ship v1.1"               # rename
skuld edit 5 --priority high --due 2026-09-01  # bump priority + set a due date
skuld edit 5 --due ""                          # clear the due date
skuld edit 5 --desc ""                         # clear the description
```

| Option | Effect |
|--------|--------|
| `--name <text>` | Rename the task (can't be empty). |
| `-d`, `--desc <text>` | Set the description (empty string clears it). |
| `--priority <level>` / `-H` | Set `standard` \| `high` (`-H` = high). |
| `--due <YYYY-MM-DD>` | Set the due date (empty string clears it). |

Requires at least one field flag (else a usage error). Every change is validated **before** the store
is touched, and refuses (rc 1) on a non-integer or nonexistent id. A name or description you set can
contain tabs/newlines — they round-trip byte-identical.

### `close`

Mark a task done (alias: `done`) — flips it to `closed` and stamps `completed` with the current time.

```sh
skuld close 3
skuld done 3     # alias
```

Closed tasks drop off `skuld list` (but still count in its footer). Re-closing an already-closed task
is a **gentle no-op** (exit 0), so an earlier completion time is never overwritten. Refuses (rc 1) on
a non-integer or nonexistent id.

### `reopen`

Reopen a closed task — flips it back to `open` and clears its `completed` stamp, so it returns to
`skuld list`.

```sh
skuld reopen 3
```

Reopening an already-open task is a gentle no-op (exit 0).

### `rm`

**Soft-delete** a task (alias: `del`) — its record moves to `$SKULD_HOME/.trash/tasks.tsv`, never an
unrecoverable delete. There is no code path in skuld that hard-deletes a task.

```sh
skuld rm 4          # confirms, then moves the record to .trash/tasks.tsv
skuld rm 4 --force  # skip the prompt
skuld del 4 --force # alias
```

| Option | Effect |
|--------|--------|
| `-f`, `--force` | Skip the confirmation prompt (`-y`/`--yes` also work). |

The record is appended to the trash ledger **before** it leaves the store, so a failed removal can
only ever duplicate a task, never lose one. The confirmation reads `/dev/tty` directly, so a
piped/redirected stdin can't silently auto-confirm — pass `--force` for that. Restore by moving the
record back into `tasks.tsv`.

---

## Read

### `list`

List tasks — your **open** ones by default: id, a `!` for high priority, name, and due date, with
overdue dates called out. Closes with a store-wide summary footer (`N open · N overdue · N done`,
always the whole store regardless of filter). Bare `skuld` is the same as `skuld list`.

```sh
skuld                       # bare skuld = list open tasks
skuld list                  # the same
skuld ls                    # alias
skuld list --all            # open + closed
skuld list --closed         # only closed
skuld list --overdue        # only overdue (open, past due)
skuld list --priority high  # only high-priority
skuld list --sort due       # order by due date
skuld list --sort due -r    # …reversed
skuld list --overdue --porcelain   # filters compose with --porcelain
```

| Option | Effect |
|--------|--------|
| `--open` | Only open tasks (the default). |
| `--closed` | Only closed tasks. |
| `--all`, `-a` | Open + closed. |
| `--overdue` | Only overdue tasks (open, with a due date before today). |
| `--priority <level>` | Only `standard` \| `high` (`-H` = `--priority high`). |
| `--sort <key>` | Order by `id` *(default)* \| `due` \| `priority` \| `created`. Ties keep id order; no-due sorts last. |
| `-r`, `--reverse` | Reverse the sort. |
| `--porcelain` | The stable, escape-free, TAB-separated column contract (no color/header/footer). |

Overdue is a lexical date compare (`due < today`) — no date math, fully portable.

### `show`

Show one task in full — status, priority, timestamps, due date, and description.

```sh
skuld show 3
skuld view 3            # alias
skuld 3                 # same, via the bareword fast-path
skuld show 3 --porcelain
```

| Option | Effect |
|--------|--------|
| `--porcelain` | Print the single record as one TAB-separated line (the same frozen column contract as `list --porcelain`). |

Refuses (rc 1) on a non-integer or nonexistent id.

---

## Setup

### `init`

Scaffold the store — the ledger `tasks.tsv` and its `.trash/` (where `rm` soft-deletes) — and write a
starter config. Idempotent — safe to run again, and it **never clobbers an existing ledger**.

```sh
skuld init
skuld init --force       # overwrite an existing config
```

| Option | Effect |
|--------|--------|
| `-f`, `--force` | Overwrite an existing config file (the ledger is never touched). |

Scaffolds whichever store the resolution ladder points at, and writes the config to `$SKULD_CONFIG`.

### The bareword fast-paths

The dispatcher is **closed** — only verbs reach the first position — with two ergonomic defaults:

```sh
skuld            # ≡ skuld list   (your open tasks — the daily driver)
skuld 3          # ≡ skuld show 3 (an integer is unambiguously not a verb)
skuld nope       # unknown, non-integer → clean error + menu, exit 1
```

---

## Scripting with `--porcelain`

For composing skuld into other tools, `list` and `show` take `--porcelain`: stable, escape-free,
TAB-separated output with **no color, header, or footer**. Every task is exactly **one line** —
`name` and `description` are backslash-encoded (`\t`, `\n`), so a tab or newline in your text never
shears the columns. The column order is frozen:

```
id ⇥ status ⇥ priority ⇥ created ⇥ due ⇥ completed ⇥ name ⇥ description
```

```sh
# how many tasks are overdue?
skuld list --overdue --porcelain | wc -l

# the names of every high-priority open task, by due date
skuld list --priority high --sort due --porcelain | cut -f7

# the due date of task 5
skuld show 5 --porcelain | cut -f5

# ids of everything closed (e.g. to archive elsewhere)
skuld list --closed --porcelain | cut -f1
```

---

## `help` & version

```sh
skuld help              # the command menu
skuld -h                # same
skuld <command> help    # detail for one command (e.g. skuld add help)
skuld --version         # print the version
skuld -V                # same
```

---

## Recipes

```sh
# First-time setup — scaffold the store, then point SKULD_HOME at a synced dir
skuld init
export SKULD_HOME="$HOME/tasks"   # e.g. a Syncthing/Dropbox/git-backed folder

# Capture tasks fast
skuld add -H --due 2026-08-01 "Ship the release"
skuld add -d "milk, eggs, coffee" "Groceries"

# The daily driver — what do I owe? (no verb needed)
skuld                              # your open tasks
skuld list --overdue               # just the fires

# Work a task and mark it done
skuld 1                            # peek at task 1
skuld close 1

# Reprioritize / reschedule without retyping
skuld edit 2 --priority high --due 2026-08-15

# End-of-week review: everything you finished
skuld list --closed

# Feed skuld into other tools (the stable contract)
skuld list --porcelain | column -t -s "$(printf '\t')"   # pretty-print the raw columns
skuld list --overdue --porcelain | cut -f7                # overdue task names
watch -n60 'skuld list --overdue'                          # a tiny overdue dashboard

# Plain output for a pipe or a log (no color, zero escapes)
NO_COLOR=1 skuld list
```
