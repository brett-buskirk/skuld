# skuld

[![Shellcheck](https://github.com/brett-buskirk/skuld/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/brett-buskirk/skuld/actions/workflows/shellcheck.yml)
[![Test](https://github.com/brett-buskirk/skuld/actions/workflows/test.yml/badge.svg)](https://github.com/brett-buskirk/skuld/actions/workflows/test.yml)

**A pocket CLI task-tracker — the ledger of what you owe your future self.**

Skuld is the Norn who governs what *shall be* — her name is cognate with "shall" and "should", and
carries the older sense of *debt, obligation, that-which-must-become*. So `skuld` is [`edda`](https://github.com/brett-buskirk/edda)'s
sibling and mirror: edda records what *was* (a vault of notes), skuld records what *shall be* (a
checklist of tasks). It's a single self-contained Bash script over one small, structured file — **no
database, no daemon, and no network, ever**. Drop it on your `PATH` and start tracking.

```sh
skuld init                                   # scaffold the store
skuld add -H --due 2026-08-01 "Ship the release"
skuld add "Buy milk"
skuld                                         # no verb → your open tasks
skuld close 1                                 # mark it done
skuld 2                                       # no verb + an id → show that task
```

## The store is sacred

`skuld`'s entire surface mutates one small file you care about — your task ledger. That sets the risk
posture, and four rules hold throughout. They are not negotiable:

- **Atomic writes.** Every mutation rewrites the whole store to a temp file *beside* it, then `mv`s
  it into place. A crash or `Ctrl-C` mid-write leaves the **previous store fully intact** — never a
  half-applied rewrite with the tail of your task list truncated off.
- **Every write lands inside the store.** `skuld` never writes outside `$SKULD_HOME`, and never
  phones home.
- **Nothing is ever hard-deleted.** `skuld rm` soft-deletes to `$SKULD_HOME/.trash/tasks.tsv` — never
  an unrecoverable delete. Restore a task by moving its record back.
- **Offline, always.** No `gh`, no `curl`, no network calls of any kind.

Point `SKULD_HOME` at a synced or version-controlled directory and the ledger travels with you — it's
state worth backing up.

## Install

`skuld` is a single, self-contained Bash script — **curl it straight onto your `PATH`:**

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/brett-buskirk/skuld/main/skuld -o ~/.local/bin/skuld
chmod +x ~/.local/bin/skuld
```

(Make sure `~/.local/bin` is on your `PATH`.) Then scaffold your store:

```sh
skuld init
```

**Requires only `bash` + coreutils** (`awk`, `sort`, `tr`, `mktemp`, `date`). Timestamps use
`date -u +%FT%TZ`, which is portable across GNU *and* BSD/macOS — so there's nothing else to install.

## Usage

```
skuld add <name…>          add a task (-H high, --due, -d desc; alias: new)
skuld list [filters]       list tasks — open by default (alias: ls)
skuld show <id>            show one task in full (alias: view)
skuld close <id>           mark a task done (alias: done)
skuld reopen <id>          reopen a closed task
skuld edit <id> [flags]    change a task's fields (--name/--desc/--priority/--due)
skuld rm <id>              soft-delete a task to .trash/ (--force to skip confirm; alias: del)
skuld init                 scaffold the store + a starter config
skuld                      no verb → list open tasks
skuld <id>                 no verb + an id → show that task
skuld help                 the menu
skuld <cmd> help           detail & options for any command
skuld version              print the version
```

The grammar is **verb-first**, with two ergonomic defaults: a bare `skuld` lists your open tasks (the
daily driver), and `skuld <id>` shows that task (an integer is unambiguously not a verb). Nothing else
free-form reaches the dispatcher — verbs always win the first position.

### `add` — capture a task

```sh
skuld add "Buy milk"                                    # open, standard priority, no due
skuld add -H "Call the plumber"                         # -H = high priority
skuld add --due 2026-08-01 -d "draft + review" "Ship"   # due date + a description
```

The **name** is the positional text; everything else is a flag. A task starts `open`, `standard`
priority, with `created` stamped automatically. `--due` accepts **only** `YYYY-MM-DD` — anything else
(`tomorrow`, `07/20/2026`, `2026-13-40`) is rejected with a clear error rather than silently stored.

### `list` — what do I owe?

```sh
skuld                       # bare skuld = list open tasks
skuld list                  # the same
skuld list --all            # open + closed
skuld list --closed         # only closed
skuld list --overdue        # only overdue (open, past due)
skuld list --priority high  # only high-priority (-H is shorthand)
skuld list --sort due       # order by due date (id | due | priority | created)
skuld list --sort due -r    # …reversed
```

The human view shows id, a `!` for high priority, the name, and the due date — with **overdue dates
called out** — and closes with a store-wide summary footer (`N open · N overdue · N done`, always the
whole store regardless of filter). Overdue is a lexical date compare (`due < today`); no date math,
fully portable.

### `show` — one task in full

```sh
skuld show 3        # status, priority, timestamps, due, description
skuld 3             # the same, via the bareword fast-path
```

### `close` / `reopen` — the state machine

```sh
skuld close 3       # → closed, stamps 'completed' (alias: done)
skuld done 3        # the same
skuld reopen 3      # → open, clears 'completed'
```

State is binary and total: `open ⇄ closed`. `close` stamps `completed` with the current time and the
task drops off `skuld list` (but still counts in the footer); `reopen` clears the stamp and brings it
back. Re-closing an already-closed task is a gentle no-op, so an earlier completion time is never
overwritten.

### `edit` — change a task's fields

```sh
skuld edit 5 --name "Ship v1.1"          # rename
skuld edit 5 --priority high --due 2026-09-01
skuld edit 5 --due ""                     # clear the due date
skuld edit 5 --desc ""                    # clear the description
```

Flag-based, so it scripts cleanly: only the fields you name change; `id`, `status`, and the timestamps
are left alone (use `close`/`reopen` for status). An empty `--due`/`--desc` clears that field; `--name`
can't be emptied (a task needs a name). Every change is validated *before* the store is touched.

### `rm` — soft-delete, never a hard delete

```sh
skuld rm 4          # confirms, then moves the record to .trash/tasks.tsv
skuld rm 4 --force  # skip the prompt (alias: del)
```

`rm` **moves** the task's record into `$SKULD_HOME/.trash/tasks.tsv` — the record is saved to the
trash *before* it leaves the store, so a failed removal can only ever duplicate a task, never lose
one. There is no code path in skuld that unrecoverably deletes a task. It confirms once (reading
`/dev/tty`, so a pipe can't auto-confirm a batch) unless you pass `--force`. Restore by moving the
record back into `tasks.tsv`.

### `init` & configuration

`skuld init` scaffolds the store (the ledger and its `.trash/`) and writes a starter config. The store
is resolved with the same ladder every command uses — **env > config file > default:**

1. `$SKULD_HOME` in the environment, else
2. `SKULD_HOME` set in the config file (`$SKULD_CONFIG`, default
   `${XDG_CONFIG_HOME:-~/.config}/skuld/config` — a plain sourced shell file), else
3. the default `${XDG_DATA_HOME:-~/.local/share}/skuld`.

`init` is idempotent and **never clobbers an existing ledger** — safe to run again.

## Scripting: `--porcelain`

For composing skuld into other tools, `list` and `show` take `--porcelain`: stable, escape-free,
TAB-separated output with **no color, header, or footer**. The column order is frozen — later versions
only ever append:

```
id ⇥ status ⇥ priority ⇥ created ⇥ due ⇥ completed ⇥ name ⇥ description
```

Every task is exactly **one line** — `name` and `description` are backslash-encoded (`\t`, `\n`), so a
tab or newline in your text never shears the columns. Decode them in your consumer if you need the raw
value.

```sh
# how many tasks are overdue?
skuld list --overdue --porcelain | wc -l

# the names of every high-priority open task, by due date
skuld list --priority high --sort due --porcelain | cut -f7

# the due date of task 5
skuld show 5 --porcelain | cut -f5
```

Respecting `NO_COLOR` and non-TTY output, the *human* views are also escape-free when piped — but
`--porcelain` is the **stable contract** you should script against.

## The store format

The ledger is a single tab-separated file at `$SKULD_HOME/tasks.tsv`, one task per line, with the
fixed columns above. Zero external dependencies — you can `grep`, `awk`, and back it up yourself:

```
1	open	high	2026-07-19T14:00:00Z	2026-08-01		Ship the release	draft + review
2	closed	standard	2026-07-19T14:01:00Z		2026-07-19T15:30:00Z	Buy milk
```

- **IDs are monotonic and never reused** — `max(id)+1`, so a deleted `#4` never returns.
- **Timestamps are ISO-8601 UTC** (`created`, `completed`); `due` is `YYYY-MM-DD`.
- **All reads and writes go through one seam**, so the documented TSV→JSONL upgrade (if tasks ever grow
  nested data) is a two-function change, not a rewrite.

## Status

**v1.0.0** — the full v1 surface in one self-contained script: `init` · `add` · `list` · `show` ·
`close`/`done` · `reopen` · `edit` · `rm`, the two bareword fast-paths, filters
(`--closed`/`--all`/`--overdue`/`--priority`), sorting (`--sort` + `--reverse`), a frozen
`--porcelain` contract, two-level help, a pipe-safe palette, atomic writes with a `.trash/`
soft-delete, and `shellcheck`- and test-gated CI (130 checks). See [ROADMAP.md](ROADMAP.md) for
what's next and [CHANGELOG.md](CHANGELOG.md) for the record.

## License

MIT — see [LICENSE](LICENSE).
