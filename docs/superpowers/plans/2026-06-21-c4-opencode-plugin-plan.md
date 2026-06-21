# C4 OpenCode Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn C4 (multi-agent AI team) into an opencode plugin accessible via `/c4` command using opencode subagents + custom tools.

**Architecture:** Main session AI reads `/c4` command prompt → spawns Leader subagent via `task` tool for planning → spawns Dev subagents for implementation → spawns Leader for review. Plugin provides validation/logging tools. No filesystem polling.

**Tech Stack:** TypeScript (`@opencode-ai/plugin` SDK), opencode agents (`.md` frontmatter), opencode commands (`.md` template).

## Global Constraints

- All new files live under `.opencode/`
- Plugin uses `@opencode-ai/plugin` SDK for types (runtime resolves automatically)
- Plugin sessions are in-memory only (no persistence in v1)
- Agents communicate via structured JSON (plan output, done report, review decision)
- No filesystem polling — all orchestration via `task` tool calls

---

## File Structure

```
c4/
├── .opencode/
│   ├── agents/
│   │   ├── c4-leader.md       ← Task 1: Leader subagent
│   │   └── c4-dev.md          ← Task 2: Dev subagent
│   ├── plugins/
│   │   └── c4-plugin.ts       ← Task 3: Plugin with custom tools
│   └── commands/
│       └── c4.md              ← Task 4: /c4 command
├── c4.sh                      ← Keep as-is
├── .c4/                       ← Keep as-is
├── AGENTS.md
└── README.md
```

---

### Task 1: Leader Agent Definition

**Files:**
- Create: `.opencode/agents/c4-leader.md`

**Interfaces:**
- Consumes: (none — this is the first task)
- Produces: Agent `c4-leader` available for `task(agent: "c4-leader", input: { goal, type })`

- [ ] **Step 1: Create `.opencode/agents/` directory**

```bash
mkdir -p .opencode/agents
```

- [ ] **Step 2: Create `c4-leader.md` agent definition**

```markdown
---
description: C4 Leader AI — breaks goals into tasks, assigns to devs, reviews results.
mode: subagent
---

You are the **Leader AI** of the C4 multi-agent system.

## Behavior

You operate in two modes, determined by the `type` field in your input.

### Mode: "plan"

Input: `{ goal: string, type: "plan" }`

Analyze the user's goal and create a detailed task plan. For each task, decide:
- What the task is (title + description)
- Acceptance criteria
- Which developer should implement it (assignedTo: "c4-dev-1", "c4-dev-2", or "c4-dev-3")

Output a valid JSON object (NO markdown wrapping, NO explanation, ONLY the JSON object):

```json
{
  "tasks": [
    {
      "id": "task-001",
      "title": "Implement login page",
      "description": "Create a login page with email/password fields",
      "criteria": ["Form with email + password inputs", "Validation on submit", "Error messages for invalid input"],
          "assignedTo": "c4-dev"
    }
  ]
}
```

Use `assignedTo: "c4-dev"` for all tasks. The orchestrator handles distribution.

### Mode: "review"

Input: `{ task: { id, title, description, criteria, assignedTo }, report: { taskId, summary, files, verification }, type: "review" }`

Review the dev's done report against the task's acceptance criteria. Decide:
- **approved:** All criteria met, quality is acceptable
- **needs_revision:** Some criteria not met or quality issues — provide specific feedback

Output a valid JSON object (NO markdown wrapping, NO explanation, ONLY the JSON object):

```json
{
  "decision": "approved"
}
```

or

```json
{
  "decision": "needs_revision",
  "feedback": "The error handling for invalid input is missing. Please add validation messages."
}
```

## Rules
- Be specific and actionable in task descriptions and review feedback
- Use `assignedTo: "c4-dev"` for all tasks
- Tasks should be atomic — each task should be completable independently
```

- [ ] **Step 3: Verify file exists**

```bash
ls -la .opencode/agents/c4-leader.md
```

Expected: file exists with correct content

- [ ] **Step 4: Commit**

```bash
git add .opencode/agents/c4-leader.md
git commit -m "feat: add C4 leader subagent definition"
```

---

### Task 2: Dev Agent Definition

**Files:**
- Create: `.opencode/agents/c4-dev.md`

**Interfaces:**
- Consumes: Agent `c4-leader` from Task 1 (for review after implementation)
- Produces: Agent `c4-dev` available for `task(agent: "c4-dev", input: { task })`

- [ ] **Step 1: Create `c4-dev.md` agent definition**

```markdown
---
description: C4 Developer AI — implements tasks assigned by the leader.
mode: subagent
---

You are a **Developer AI** of the C4 multi-agent system.

## Behavior

Input: `{ task: { id, title, description, criteria, assignedTo } }`

Implement the task. Read the description and acceptance criteria carefully. Write real, working code. After implementation, output a done report as a valid JSON object (NO markdown wrapping, NO explanation, ONLY the JSON object):

```json
{
  "taskId": "task-001",
  "summary": "Created login page with email/password form, validation, and error handling",
  "files": ["src/pages/Login.tsx", "src/components/LoginForm.tsx"],
  "verification": "Run `npm run dev` and navigate to /login. The form should show validation errors for empty fields."
}
```

## Rules
- Write real, working code — no placeholders
- Verify all acceptance criteria are met before reporting done
- List all files created or modified
- Provide clear verification steps
- If blocked, include that in the summary
```

- [ ] **Step 2: Verify file exists**

```bash
ls -la .opencode/agents/c4-dev.md
```

Expected: file exists with correct content

- [ ] **Step 3: Commit**

```bash
git add .opencode/agents/c4-dev.md
git commit -m "feat: add C4 dev subagent definition"
```

---

### Task 3: Plugin with Custom Tools

**Files:**
- Create: `.opencode/plugins/c4-plugin.ts`

**Interfaces:**
- Consumes: (none — standalone plugin)
- Produces: Custom tools `c4_init`, `c4_validate_plan`, `c4_validate_report`, `c4_log` available to main session AI
- Produces: Session state management (in-memory Map)

- [ ] **Step 1: Create `.opencode/plugins/` directory**

```bash
mkdir -p .opencode/plugins
```

- [ ] **Step 2: Create `c4-plugin.ts`**

```typescript
import type { Plugin } from "@opencode-ai/plugin"

interface Task {
  id: string
  title: string
  description: string
  criteria: string[]
  assignedTo: string
}

interface Plan {
  tasks: Task[]
}

interface DoneReport {
  taskId: string
  summary: string
  files: string[]
  verification: string
}

interface ReviewDecision {
  decision: "approved" | "needs_revision"
  feedback?: string
}

interface Session {
  id: string
  goal: string
  tasks: Task[]
  results: Map<string, { report: DoneReport; decision?: ReviewDecision; revisionCount: number }>
  status: "active" | "completed" | "failed"
  createdAt: Date
}

const sessions = new Map<string, Session>()

export default (async () => {
  return {
    tool: {
      c4_init: {
        description: "Initialize a new C4 session. Call this first when starting a /c4 command.",
        args: {
          goal: { type: "string", description: "The goal to accomplish" },
        },
        async execute(args: { goal: string }) {
          const session: Session = {
            id: crypto.randomUUID(),
            goal: args.goal,
            tasks: [],
            results: new Map(),
            status: "active",
            createdAt: new Date(),
          }
          sessions.set(session.id, session)
          return { sessionId: session.id }
        },
      },

      c4_validate_plan: {
        description: "Validate a plan returned by the Leader subagent. Helps catch malformed responses early.",
        args: {
          plan: { type: "string", description: "The raw plan JSON string from the Leader subagent" },
        },
        async execute(args: { plan: string }) {
          try {
            const parsed: Plan = JSON.parse(args.plan)
            if (!Array.isArray(parsed.tasks) || parsed.tasks.length === 0) {
              return { valid: false, errors: ["Plan must contain a non-empty tasks array"] }
            }
            for (const t of parsed.tasks) {
              if (!t.id || !t.title || !t.description || !Array.isArray(t.criteria) || !t.assignedTo) {
                return { valid: false, errors: [`Task ${t.id || "unknown"} missing required fields (id, title, description, criteria, assignedTo)`] }
              }
            }
            return { valid: true, errors: [] }
          } catch {
            return { valid: false, errors: ["Plan is not valid JSON"] }
          }
        },
      },

      c4_validate_report: {
        description: "Validate a done report returned by a Dev subagent.",
        args: {
          report: { type: "string", description: "The raw report JSON string from the Dev subagent" },
        },
        async execute(args: { report: string }) {
          try {
            const parsed: DoneReport = JSON.parse(args.report)
            if (!parsed.taskId || !parsed.summary || !Array.isArray(parsed.files) || !parsed.verification) {
              return { valid: false, errors: ["Report missing required fields (taskId, summary, files, verification)"] }
            }
            return { valid: true, errors: [] }
          } catch {
            return { valid: false, errors: ["Report is not valid JSON"] }
          }
        },
      },

      c4_log: {
        description: "Log a C4 event. Use for tracking task progress, errors, and decisions.",
        args: {
          message: { type: "string", description: "The log message" },
          level: { type: "string", description: "Log level: info, warn, error" },
        },
        async execute(args: { message: string; level: string }) {
          const ts = new Date().toISOString()
          const line = `[${ts}] [C4] [${args.level.toUpperCase()}] ${args.message}`
          // Append to events.md if .c4/ exists
          try {
            const fs = await import("fs/promises")
            await fs.appendFile(".c4/_log/events.md", line + "\n", "utf-8")
          } catch {
            // .c4/_log/events.md might not exist yet — silently skip
          }
          return { logged: true }
        },
      },
    },
  }
})
```

- [ ] **Step 3: Verify TypeScript syntax**

```bash
npx tsc --noEmit --strict --moduleResolution bundler .opencode/plugins/c4-plugin.ts 2>&1 || true
```

Expected: may show warnings about `@opencode-ai/plugin` types not being installed — that's fine, the file is consumed at runtime by opencode's bun runtime.

- [ ] **Step 4: Commit**

```bash
git add .opencode/plugins/c4-plugin.ts
git commit -m "feat: add C4 plugin with session management and validation tools"
```

---

### Task 4: /c4 Command

**Files:**
- Create: `.opencode/commands/c4.md`

**Interfaces:**
- Consumes: All tools from Task 3 (`c4_init`, `c4_validate_plan`, `c4_validate_report`, `c4_log`) + agents from Tasks 1 & 2 (`c4-leader`, `c4-dev`)
- Produces: `/c4 <goal>` command ready for user use

- [ ] **Step 1: Create `.opencode/commands/` directory**

```bash
mkdir -p .opencode/commands
```

- [ ] **Step 2: Create `c4.md` command**

```markdown
---
description: Run the C4 multi-agent team on a goal. Spawns a Leader subagent to plan, Dev subagents to implement, and Leader to review results.
agent: general
---

# C4 Multi-Agent Orchestration

The user's goal is: $ARGUMENTS

You are the **C4 Orchestrator**. Follow this protocol step by step. Do NOT skip steps. Do NOT combine steps.

## Step 1: Initialize Session

Call the `c4_init` tool with the goal to create a new C4 session.

## Step 2: Plan with Leader

Use the `task` tool to spawn the Leader subagent:

```
task(agent: "c4-leader", input: { goal: "$ARGUMENTS", type: "plan" })
```

The Leader will return a JSON plan string. Call `c4_validate_plan` tool with the raw response to validate it. If invalid, retry the task call once. If still invalid, stop and report the error.

Parse the validated plan to get the task list. Respect each task's `assignedTo` field — the Leader decides which dev does what.

## Step 3: Implement Tasks

For each task in the plan (process them in the order returned by the Leader):

### 3a. Assign to Developer

Use the `task` tool to spawn the Dev subagent. The `assignedTo` field from the Leader's plan is used for tracking/logging — always use agent `c4-dev`:

```
task(agent: "c4-dev", input: { task: { id, title, description, criteria, assignedTo } })
```

Wait for the Dev to return a done report. Call `c4_validate_report` tool with the raw response. If invalid, retry once.

### 3b. Review with Leader

Use the `task` tool to spawn the Leader subagent for review:

```
task(agent: "c4-leader", input: { task: { id, title, description, criteria, assignedTo }, report: { taskId, summary, files, verification }, type: "review" })
```

The Leader will return a decision (approved or needs_revision with feedback).

### 3c. Handle Revision

- If **approved**: Mark the task as done in your tracking. Call `c4_log` with message: "Task {id} approved".
- If **needs_revision** and revision count < 3: Go back to Step 3a, appending the Leader's feedback to the task input. Increment revision count.
- If **needs_revision** and revision count >= 3: Call `c4_log` with level "error" and message: "Task {id} failed after 3 revisions". Mark task as failed.

## Step 4: Report

After all tasks are processed, report to the user with:
- A summary of all tasks and their status
- Which tasks were approved
- Which tasks failed (if any)
- A list of all files created or modified across all tasks

## Rules
- Process tasks in the EXACT order returned by the Leader
- Use the `assignedTo` field from the Leader's plan — the Leader decides assignment
- Call `c4_log` after each significant step (plan received, task assigned, task completed, task approved, error)
- If a subagent call times out or returns garbage, retry ONCE then fail that task
- Always wait for each subagent to complete before moving to the next step
```

- [ ] **Step 3: Verify file exists**

```bash
ls -la .opencode/commands/c4.md
```

Expected: file exists with correct content

- [ ] **Step 4: Commit**

```bash
git add .opencode/commands/c4.md
git commit -m "feat: add /c4 command for multi-agent team orchestration"
```

---

### Task 5: Integration Verification

**Files:**
- (none — this is a test task)

**Interfaces:**
- Consumes: All files from Tasks 1-4

- [ ] **Step 1: Verify complete file structure**

```bash
find .opencode -type f | sort
```

Expected:
```
.opencode/agents/c4-dev.md
.opencode/agents/c4-leader.md
.opencode/commands/c4.md
.opencode/plugins/c4-plugin.ts
```

- [ ] **Step 2: Do a dry-run validation by reading each file**

Read each file and verify:
- `c4-leader.md`: has agent frontmatter, plan mode output format JSON
- `c4-dev.md`: has agent frontmatter, implement mode output format JSON
- `c4-plugin.ts`: exports default async function, registers `c4_init`, `c4_validate_plan`, `c4_validate_report`, `c4_log`
- `c4.md`: has command frontmatter, describes all 4 protocol steps

- [ ] **Step 3: Commit final state**

```bash
git add -A
git commit -m "chore: complete C4 opencode plugin setup"
```
