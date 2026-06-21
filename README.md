# C4 — Multi-Agent AI Plugin

[![CI](https://github.com/rolniuq/c4/actions/workflows/ci.yml/badge.svg)](https://github.com/rolniuq/c4/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/language-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![OpenCode](https://img.shields.io/badge/opencode-plugin-6C47FF.svg)](https://opencode.ai)

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

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/rolniuq/c4/main/c4.sh | sudo tee /usr/local/bin/c4 > /dev/null && sudo chmod +x /usr/local/bin/c4
```

That's it. No clone needed.

---

## Quick Start

```bash
# Install C4 into any project with one command
c4 install ~/your-project

# Register your AI agents
cd ~/your-project
./c4.sh register leader "Claude" "Claude Code"
./c4.sh register dev-1  "Copilot" "GitHub Copilot"
./c4.sh register dev-2  "Claude" "Cursor"

# Each Dev AI starts watching (run in separate terminals)
./c4.sh watch dev-1   # Terminal 2
./c4.sh watch dev-2   # Terminal 3

# Leader watches and receives your goal
./c4.sh watch leader  # Terminal 1 — then drop a goal.md

# When task is done
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

## OpenCode Plugin

C4 is also an **OpenCode plugin**. When you run OpenCode in a C4 project, you get the `/c4` command — a multi-agent team at your fingertips.

### Quick Start (OpenCode)

```bash
# 1. Install C4 globally
curl -fsSL https://raw.githubusercontent.com/rolniuq/c4/main/c4.sh | sudo tee /usr/local/bin/c4 > /dev/null && sudo chmod +x /usr/local/bin/c4

# 2. Navigate to your project
cd ~/your-project

# 3. Install C4 (includes .opencode/ plugin)
c4 install .

# 4. Start OpenCode
opencode

# 5. Run any goal:
/c4 implement a REST API with authentication
```

The `/c4` command spawns:
1. **Leader subagent** — analyzes your goal, creates a task plan, assigns work
2. **Dev subagent** — implements each task, reports back
3. **Leader review** — reviews results, approves or requests revision

All communication is event-driven via OpenCode's `task` tool — no filesystem polling, no race conditions.

### Manual Plugin Setup

If you already have C4 installed, enable the OpenCode plugin manually:

```bash
# Copy the OpenCode plugin into your project
cp -r .opencode ~/your-project/.opencode
```

Or reference it from your project's `opencode.json`:

```json
{
  "plugin": ["./path/to/c4/.opencode/plugins/c4-plugin.ts"]
}
```

### Requirements

- [OpenCode](https://opencode.ai) (latest version)
- The C4 `.opencode/` directory in your project root

---

## Install Globally

```bash
curl -fsSL https://raw.githubusercontent.com/rolniuq/c4/main/c4.sh | sudo tee /usr/local/bin/c4 > /dev/null && sudo chmod +x /usr/local/bin/c4

# Now install C4 into any project with one command:
c4 install ~/path/to/your-project
```
