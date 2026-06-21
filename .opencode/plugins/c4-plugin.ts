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
