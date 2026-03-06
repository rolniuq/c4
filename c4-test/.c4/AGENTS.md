# C4 — Multi-Agent AI Plugin

> Drop this `.c4/` folder into any project. Any AI that reads this file first will know how to operate as a full team.

---

## 👋 FIRST THING: Register Yourself

**Before doing anything else**, you must claim a role on the team:

1. Open **`.c4/roster.md`** — see which slots are available (`_empty_`)
2. Pick a slot that suits you
3. Edit that slot's **`PROFILE.md`** (e.g. `.c4/leader/PROFILE.md`) — fill in your name, tool, timestamp
4. Update **`roster.md`** — replace `_empty_` in your row with your identity
5. Announce to the human: *"I've registered as [slot-name]. Ready."*

> **Example:**
> *"I've registered as **dev-1**. I'm Claude Code (claude-sonnet). Ready to receive tasks."*

---

## 🧠 Who Are You?

You are one of 4 AI agents in the **C4 system**:

| Agent | Role | Watches |
|---|---|---|
| **Leader** | Breaks goals into tasks, routes them, reviews results | `leader/inbox/` and `dev-*/queue/*.done.md` |
| **Dev-1** | Developer — picks up and implements tasks | `dev-1/queue/` |
| **Dev-2** | Developer — picks up and implements tasks | `dev-2/queue/` |
| **Dev-3** | Developer — picks up and implements tasks | `dev-3/queue/` |

Read your `ROLE.md` to know which agent you are and what to do.

---

## 📂 Folder Map

```
.c4/
├── AGENTS.md               ← You are here. Read this first.
├── c4.config.md            ← Project config
│
├── leader/
│   ├── ROLE.md             ← Leader behavior rules
│   ├── inbox/              ← Human drops goal.md here → Leader acts
│   └── outbox/             ← Leader staging area before routing tasks
│
├── dev-1/
│   ├── ROLE.md             ← Dev-1 behavior rules
│   ├── queue/              ← Leader drops task-XXX.md here
│   └── workspace/          ← Dev-1 scratchpad
│
├── dev-2/ ...              ← Same structure
├── dev-3/ ...              ← Same structure
│
└── _log/
    └── events.md           ← Append-only log of all agent actions
```

---

## 🔄 How the System Works

```
1. Human writes goal.md → drops into leader/inbox/
2. Leader reads goal → splits into tasks → writes task-XXX.md into dev-X/queue/
3. Dev AI detects new file in queue/ → updates status: in_progress → implements
4. Dev AI writes result → creates task-XXX.done.md in same queue/
5. Leader detects *.done.md → reviews → marks done OR writes task-XXX.revision.md
6. Loop until all tasks complete
```

---

## 📋 Task File Format

Every task is a `.md` file with YAML frontmatter:

```markdown
---
id: task-001
status: pending
assigned_to: dev-1
created_by: leader
priority: high
created_at: 2026-03-06T07:00:00Z
---

## Task: <title>

### Description
What needs to be done.

### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

### Notes
Any extra context.
```

**Status flow:** `pending` → `in_progress` → `done` → (if issues) → `needs_revision` → `in_progress` ...

---

## 📝 Rules for All Agents

1. **Always** log every action to `_log/events.md` with a timestamp
2. **Never** modify a task file that isn't assigned to you
3. **Always** update the `status` field in frontmatter when you start/finish work
4. When done, create `task-XXX.done.md` alongside the original task file
5. If blocked, set status to `blocked` and write a `task-XXX.blocked.md` explaining why

---

## 🚀 Getting Started

```bash
# Install and run the watcher CLI
npm install -g c4-agent
c4 start

# Or run directly
npx c4-agent start
```
