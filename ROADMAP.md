# Roadmap

_What's planned for skuld — check items off as they ship. Each phase is a focused PR._

## Shipped
- [x] **v1.0.0 — the complete v1 task-tracker** · one self-contained script built to the
  locked design: `init` · `add` · `list` · `show` · `close`/`done` · `reopen` · `edit` ·
  `rm`, with the two bareword fast-paths (`skuld` → list, `skuld <id>` → show). The storage
  seam (`store_read`/`store_write`) with **atomic writes** and TSV↔US encode/decode; the
  binary `open ⇄ closed` state machine; soft-delete to `.trash/` behind the `/dev/tty`
  `confirm()` gate; list filters (`--closed`/`--all`/`--overdue`/`--priority`) and sorting
  (`--sort` + `--reverse`); the frozen `--porcelain` column contract; the
  `env > config > default` store ladder; verb-first grammar with a closed dispatcher;
  two-level help; a `NO_COLOR`/non-TTY-aware palette; and `shellcheck`- and test-gated CI
  (130 checks).

## Next (nice-to-have, roughly in order)
- [ ] **`stats`** · a quick summary — counts by status/priority, overdue, throughput.
- [ ] **Natural-language dues** · accept `tomorrow`, `+3d`, `friday` for `--due`, gated
  behind a `have gdate` check (needs GNU `date -d`; BSD uses `-v`), degrading to the strict
  `YYYY-MM-DD` when absent.
- [ ] **`restore`** · pull a task back out of `.trash/tasks.tsv` by id (today it's a manual
  move).
- [ ] **Tags / projects** · a light way to group tasks beyond priority.
- [ ] **`cancelled` state** · a third state distinct from `closed` (done vs. abandoned).
- [ ] **`flock` on writes** · cheap insurance against two simultaneous `add`s colliding on
  an id (gated on `have flock`, since macOS lacks it).

## Maybe someday (not planned)
- Recurring tasks, subtasks, reminders/notifications.
- Full calendar validation of `--due` (rejecting e.g. Feb 30 — needs date math).
- A **JSONL store** upgrade if tasks grow nested data (subtasks, tags, history). The
  `store_read`/`store_write` seam exists precisely so this is a two-function change, not a
  rewrite — the rest of the tool never sees the on-disk format.

## Out of scope (by design)
These aren't backlog — they're deliberately not what skuld is for.

- **Anything networked.** No `gh`, no `curl`, no sync-over-the-wire. The store is a plain
  file; point `SKULD_HOME` at a synced/versioned directory and let *that* own the network.
- **Any hard delete of a task.** There is no code path that unrecoverably removes a task —
  `rm` only ever soft-deletes to `.trash/`.
- **A general datastore.** The record schema is small and fixed; skuld is a checklist over a
  structured file, not a database.
