# C4 — Multi-Agent AI Plugin

> A file-system-based AI team plugin. Drop `.c4/` + `c4.sh` into any project and get a self-organizing team of AI agents: 1 Leader + 3 Developers.

**Zero dependencies. Pure bash. Works with Go, Python, Node, Rust — any project.**

---

## How It Works

```
You write a goal.md
        ↓
Leader AI splits it into tasks → routes to dev-1, dev-2, dev-3 queues
        ↓
Each Dev AI runs: ./c4.sh watch dev-X  → tasks stream into their terminal
        ↓
Dev implements → runs: ./c4.sh done dev-X task-001 "what I did"
        ↓
Leader reviews .done.md → approves or requests revision
```

All communication happens via `.md` files with YAML frontmatter. Every action is logged to `.c4/_log/events.md`.

---

## Quick Start

```bash
# 1. Copy plugin into your project (any language)
cp c4.sh your-project/
cp -r .c4/ your-project/.c4/
chmod +x your-project/c4.sh

cd your-project

# 2. Register your AI agents
./c4.sh register leader "Claude" "Claude Code"
./c4.sh register dev-1  "Copilot" "GitHub Copilot"
./c4.sh register dev-2  "Claude" "Cursor"

# 3. Each Dev AI starts watching (run in separate terminals)
./c4.sh watch dev-1   # Terminal 2
./c4.sh watch dev-2   # Terminal 3

# 4. Leader watches and receives your goal
./c4.sh watch leader  # Terminal 1 — then drop a goal.md

# 5. When task is done
./c4.sh done dev-1 task-001 "implemented GET /health in main.go"
```

---

## All Commands

```bash
./c4.sh roster                             # See who's on the team
./c4.sh register <slot> <name> <tool>      # AI claims a role
./c4.sh release <slot>                     # Free up a slot
./c4.sh watch <slot>                       # Block & stream tasks (run once per AI)
./c4.sh done <slot> <task-id> "summary"   # Mark task complete
./c4.sh reset                              # Wipe everything, start fresh
```

**Slots:** `leader`, `dev-1`, `dev-2`, `dev-3`

---

## Folder Structure

```
your-project/
├── c4.sh                   ← The CLI (copy this in)
└── .c4/
    ├── AGENTS.md           ← AI reads this first (registration + rules)
    ├── roster.md           ← Live team board (auto-updated)
    ├── c4.config.md        ← Config
    ├── leader/
    │   ├── ROLE.md         ← Leader behavior rules
    │   ├── PROFILE.md      ← Leader's identity (filled on register)
    │   ├── inbox/          ← Drop goal.md here → Leader acts
    │   └── outbox/         ← Processed goals
    ├── dev-1/              ← Backend specialist
    │   ├── ROLE.md
    │   ├── PROFILE.md
    │   ├── queue/          ← task-XXX.md + task-XXX.done.md
    │   └── workspace/
    ├── dev-2/              ← Frontend specialist
    ├── dev-3/              ← DevOps/Testing specialist
    └── _log/
        └── events.md       ← Append-only event log
```

---

## Task Lifecycle

```
pending → in_progress → done → approved
                             ↘ needs_revision → in_progress ...
```

Each task is a `.md` file with YAML frontmatter:

```markdown
---
id: task-001
status: pending
assigned_to: dev-1
priority: high
---

## Task: Implement /health endpoint

### Acceptance Criteria
- [ ] Returns 200 with { status: "ok" }
- [ ] Works in production build
```

---

## Using with Claude Code / Copilot

**Leader AI** — paste this prompt:
```
Read .c4/AGENTS.md, register as leader, then run: ./c4.sh watch leader
```

**Dev AI** — paste this prompt:
```
Read .c4/AGENTS.md, register as dev-1, then run: ./c4.sh watch dev-1
When a task appears in your terminal, implement it, then run:
./c4.sh done dev-1 <task-id> "what you did"
```

---

## Install Globally (optional)

```bash
sudo cp c4.sh /usr/local/bin/c4
# Then use: c4 roster, c4 watch dev-1, c4 reset ...
```
