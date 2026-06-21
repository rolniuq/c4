# C4 OpenCode Plugin — Design Spec

## Goal

Turn C4 (multi-agent AI team) into an opencode plugin accessible via `/c4` command. Agents run as opencode subagents, communicate via event-driven protocol (no filesystem polling), with full Leader autonomy.

## Architecture

```
User: "/c4 $goal"
    │
    ▼
c4.md (command) ──trigger──▶ c4-plugin.ts (orchestrator)
                                  │
                          SessionManager
                          ┌──────────────────────────┐
                          │ Session {                 │
                          │   id, goal, status,       │
                          │   tasks: Task[]           │
                          │   createdAt               │
                          │ }                         │
                          └──────────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
            LeaderAgent      DevAgent-1    DevAgent-2
            (subagent)       (subagent)    (subagent)
            plan, review     implement     implement
                    │             │             │
                    └─────────────┼─────────────┘
                                  │
                          Event Bus (in-memory)
```

## Components

### 1. Command (`c4.md`) — The Orchestrator

- **Path:** `.opencode/commands/c4.md`
- **Trigger:** `/c4 <goal>`
- **Purpose:** Nhận goal từ user, kích hoạt toàn bộ C4 pipeline
- **Mechanism:** Command template là prompt hướng dẫn AI chính (main session) thực hiện orchestration bằng cách gọi `task` tool và custom tools từ plugin
- **Flow trong prompt:**
  1. Gọi `c4_init` để tạo Session
  2. Gọi `task` với agent `c4-leader` để lập kế hoạch
  3. Duyệt tasks → gọi `task` với agent `c4-dev` để implement
  4. Gọi `task` với agent `c4-leader` để review từng task
  5. Loop revision nếu cần
  6. Báo cáo kết quả cho user

### 2. Plugin (`c4-plugin.ts`) — Supporting Tools

- **Path:** `.opencode/plugins/c4-plugin.ts`
- **Tech:** TypeScript, `@opencode-ai/plugin` SDK
- **Responsibilities:**
  - Register custom tools: `c4_init`, `c4_validate_plan`, `c4_validate_report`
  - Quản lý Session state in-memory
  - Validate structured data từ agents (JSON schema)
  - Cung cấp error recovery hooks
  - Custom tool: `c4_log` — ghi log vào `_log/events.md`
- **Note:** Plugin KHÔNG spawn subagents trực tiếp. Việc spawn agents do main session AI thực hiện qua `task` tool theo hướng dẫn trong command prompt.

### 3. Leader Agent (`c4-leader.md`)

- **Path:** `.opencode/agents/c4-leader.md`
- **Mode:** `subagent`
- **Full autonomy:**
  - Phân tích goal → quyết định số lượng task
  - Quyết định task nào assign cho dev nào (bằng `assignedTo` field)
  - Quyết định thứ tự assign (tuần tự / parallel)
  - Review kết quả dev → approve hoặc request revision với feedback cụ thể
- **Input format:** `{ goal: string, type: 'plan' | 'review' }` (phân biệt mode)
- **Output format (plan mode):** `{ tasks: [{ id, title, description, criteria, assignedTo }] }`
- **Output format (review mode):** `{ decision: 'approved'|'needs_revision', feedback?: string }`

### 4. Dev Agent (`c4-dev.md`)

- **Path:** `.opencode/agents/c4-dev.md`
- **Mode:** `subagent`
- **Responsibilities:**
  - Nhận task từ main session AI (theo chỉ định `assignedTo` của Leader)
  - Implement, verify acceptance criteria
  - Trả về DoneReport
- **Input format:** `{ task: { id, title, description, criteria } }`
- **Output format:** `{ taskId, summary, files: string[], verification: string }`

## Communication Protocol

### Flow

```
0. User runs /c4 <goal>
   → c4.md command prompt activated
   → Main session AI becomes "Orchestrator"

1. AI calls custom tool c4_init({ goal })
   → Plugin creates Session, returns sessionId

2. AI calls task(agent: "c4-leader", input: { goal, type: "plan" })
   → Leader subagent returns Plan
   → AI calls c4_validate_plan(plan) via plugin tool
   → Plugin validates + stores in Session

3. AI iterates through tasks (respects Leader's assignedTo + order):
   a. AI calls task(agent: "c4-dev-{assignedTo}", input: { task })
      → Dev subagent returns DoneReport
      → AI calls c4_validate_report(report) via plugin tool

   b. AI calls task(agent: "c4-leader", input: { type: "review", task, report })
      → Leader returns decision: approve | needs_revision + feedback

   c. if needs_revision && revisionCount < 3:
        AI loops to step 3a with feedback appended
      elif revisionCount >= 3:
        AI marks task as failed via c4_log tool

4. AI reports to user: summary, approved[], failed[]
```

### Key Properties

- **Main session AI = Orchestrator** — đọc command prompt, thực hiện từng bước
- **Plugin = Validator + State manager** — tools để validate data, log, quản lý session
- **Leader = Strategist** — quyết định tasks, assignment, review
- **Dev = Executor** — implement tasks, báo cáo kết quả
- **No filesystem polling** — tất cả qua `task` tool calls + plugin tools
- **MAX_RETRIES = 3** per task — prevent infinite loops

## Custom Tools (registered by plugin)

| Tool | Input | Output | Description |
|---|---|---|---|
| `c4_init` | `goal: string` | `{ sessionId: string }` | Khởi tạo Session |
| `c4_validate_plan` | `plan: object` | `{ valid: boolean, errors?: string[] }` | Validate plan từ Leader |
| `c4_validate_report` | `report: object` | `{ valid: boolean, errors?: string[] }` | Validate done report từ Dev |
| `c4_log` | `message: string, level: string` | `void` | Ghi log vào event log |

**Note:** `c4_plan`, `c4_assign`, `c4_review` KHÔNG phải custom tools — chúng là `task` tool calls với agent `c4-leader` / `c4-dev`. Plugin tools chỉ handle validation và state management.

## Error Handling

| Scenario | Response |
|---|---|
| Subagent timeout (>5m) | Mark task `failed`, continue others |
| Malformed response | Retry with stricter prompt |
| Leader rejects >3x | Mark task `failed`, notify user |
| Plugin crash | Session lost — user re-runs `/c4` |

## File Structure

```
c4/
├── .opencode/
│   ├── commands/
│   │   └── c4.md              ← /c4 command
│   ├── agents/
│   │   ├── c4-leader.md       ← Leader subagent
│   │   └── c4-dev.md          ← Dev subagent
│   └── plugins/
│       └── c4-plugin.ts       ← Plugin: session + tools + orchestration
├── c4.sh                      ← Keep as-is (optional)
├── .c4/                       ← Keep as-is (template reference)
├── AGENTS.md
└── README.md
```

## Non-goals

- Persistence (Session in-memory, loss on crash — acceptable for v1)
- File-based state (.md files) — replaced by in-memory Session
- UI/monitoring dashboard
- Cross-project session sharing
