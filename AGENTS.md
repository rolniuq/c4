# C4 — Multi-Agent AI Plugin (the project itself)

This is the source repository for **C4**, a file-system-based multi-agent AI team plugin. It's a bash CLI (`c4.sh`) + a `.c4/` template directory that gets installed into any project to give it a self-organizing team of 4 AI agents (1 Leader + 3 Developers).

## Project Structure

```
c4/
├── AGENTS.md              ← This file. Instructions for working on C4 itself.
├── c4.sh                  ← The CLI: install, register, watch, done, reset, roster
├── README.md              ← User-facing docs
├── .gitignore
└── .c4/                   ← Template that c4.sh installs into target projects
    ├── AGENTS.md          ← Template AGENTS.md for C4 users
    ├── c4.config.md       ← Template config
    ├── roster.md          ← Template team board
    ├── leader/
    │   ├── ROLE.md        ← Leader behavior rules (template)
    │   ├── PROFILE.md     ← Leader registration profile (template)
    │   ├── inbox/         ← Where goal.md files go
    │   └── outbox/        ← Processed goals
    ├── dev-1/
    │   ├── ROLE.md
    │   ├── PROFILE.md
    │   ├── queue/
    │   └── workspace/
    ├── dev-2/ ...         ← Same structure
    ├── dev-3/ ...         ← Same structure
    └── _log/
        └── events.md      ← Append-only event log (template)
```

## What C4 Does

C4 installs into any project (Go, Python, Node, Rust — any language) and enables a team of AI agents:

1. **Human** writes `goal.md` → drops into `leader/inbox/`
2. **Leader AI** reads goal → splits into tasks → writes `task-XXX.md` into dev queues
3. **Dev AI** detects task → implements → writes `task-XXX.done.md`
4. **Leader** reviews → approves or requests revision

## Tech Stack & Conventions

- **Language:** Pure bash (`set -euo pipefail`)
- **Dependencies:** Zero. Uses only POSIX + common UNIX tools (awk, grep, sed, mktemp, find, date, realpath)
- **State:** File-system-based. All state lives in `.md` files with YAML frontmatter
- **Communication:** Agents communicate via file creation/editing (inbox/queue/done files)
- **Frontmatter:** YAML between `---` fences at the top of `.md` files, managed by `fm_get`/`fm_set` helpers
- **Logging:** Append-only `_log/events.md` with `[TIMESTAMP] [AGENT] MESSAGE` format

## Key Patterns

- Shell functions follow `cmd_<name>()` naming for command dispatch
- Each function has a clear, single responsibility
- Colors/UI helpers at the top (ok, err, info, log)
- Frontmatter helpers: `fm_get`, `fm_set`, `fm_body` — used to parse/manipulate YAML in `.md` files
- Watch loops poll every 2 seconds (`WATCH_INTERVAL`)
- Valid slots: `leader`, `dev-1`, `dev-2`, `dev-3`
- The `.c4/` directory serves as both C4's own config AND the template for target projects

## How to Work on C4

- `c4.sh` is the single file that contains the entire CLI
- Template files under `.c4/` are embedded as heredocs in `cmd_install()`
- If you add a new template file, update both the heredoc in `cmd_install()` and the `mkdir -p` list
- Test by running `./c4.sh install /tmp/test-project` and checking the output
- Keep zero-dependency — no npm, no pip, no brew
- When editing `.c4/` templates, remember they'll be read by AI agents (Claude, Copilot, etc.) — keep instructions clear and unambiguous
- If adding a new command, add it to `cmd_help()` and the `case` dispatch at the bottom

## DONE Protocol — MUST Follow Before Claiming Completion

**Before saying DONE on any change, you MUST run this gate:**

```bash
make precommit
```

This runs (in order):
1. **`make clean`** — removes `.tmp`, `.cache`, `.turbo`, `dist/`, `build/`, `out/`
2. **`make lint`** — validates bash syntax, checks all expected files exist
3. **`make test`** — runs `tests/run.sh` (frontmatter validation, command sandbox tests, plugin validation, pattern enforcement)

### Gate Rules

- `make precommit` must exit **0** (all passed). If not, fix the failures.
- **No `TODO` / `FIXME` / `HACK`** in any code file (docs are exempt).
- **No build artifacts** (`.tmp`, `dist/`, `build/`, `out/`, `.turbo/`) committed.
- **No emoji/non-ASCII** in frontmatter `description` fields (may confuse AI parsers).
- **All `.opencode/agents/*.md` must have `mode: subagent`** in frontmatter.
- **Plugin tools** (`c4_init`, `c4_validate_plan`, `c4_validate_report`, `c4_log`) must all be present.
- **c4.sh functions** must follow `cmd_<name>()`, `fm_*()`, `sync_*()`, or `watch_*()` naming.
- **Pre-commit hook** installed via `git config core.hooksPath .githooks`.

### Sanity Check

```bash
# Quick check without full suite
bash -n c4.sh                           # syntax
grep -r "TODO\|FIXME\|HACK" c4.sh .opencode/  # no debt markers
make clean                              # no artifacts
make test                               # full suite
```
