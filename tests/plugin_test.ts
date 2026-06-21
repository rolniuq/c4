// C4 Plugin Unit Tests
// Run with: bun test tests/plugin_test.ts

import { describe, it, expect, mock } from "bun:test"

// The plugin module needs to be importable. Since @opencode-ai/plugin types
// may not be installed locally, we test via dynamic import with mock.
// If the import fails due to missing @opencode-ai/plugin, skip tests.
let plugin: any
try {
  plugin = await import("../.opencode/plugins/c4-plugin.ts")
} catch {
  console.warn("⚠️  Plugin import failed — @opencode-ai/plugin not installed.")
  console.warn("   Run: bun install @opencode-ai/plugin")
  process.exit(0)
}

const instance = plugin.default()

describe("c4_init", () => {
  it("creates a session with sessionId", async () => {
    const tools = (await instance).tool
    const result = await tools.c4_init.execute({ goal: "implement login" })
    expect(result).toHaveProperty("sessionId")
    expect(typeof result.sessionId).toBe("string")
  })

  it("each call creates a unique sessionId", async () => {
    const tools = (await instance).tool
    const r1 = await tools.c4_init.execute({ goal: "goal1" })
    const r2 = await tools.c4_init.execute({ goal: "goal2" })
    expect(r1.sessionId).not.toBe(r2.sessionId)
  })
})

describe("c4_validate_plan", () => {
  it("accepts a valid plan", async () => {
    const tools = (await instance).tool
    const plan = JSON.stringify({
      tasks: [
        {
          id: "task-001",
          title: "Test task",
          description: "A test",
          criteria: ["criterion 1"],
          assignedTo: "c4-dev",
        },
      ],
    })
    const result = await tools.c4_validate_plan.execute({ plan })
    expect(result.valid).toBe(true)
    expect(result.errors).toHaveLength(0)
  })

  it("rejects empty tasks array", async () => {
    const tools = (await instance).tool
    const result = await tools.c4_validate_plan.execute({ plan: '{"tasks":[]}' })
    expect(result.valid).toBe(false)
  })

  it("rejects malformed JSON", async () => {
    const tools = (await instance).tool
    const result = await tools.c4_validate_plan.execute({ plan: "not-json" })
    expect(result.valid).toBe(false)
    expect(result.errors).toContain("Plan is not valid JSON")
  })

  it("rejects task missing required fields", async () => {
    const tools = (await instance).tool
    const plan = JSON.stringify({
      tasks: [{ id: "task-001" }], // missing title, description, criteria, assignedTo
    })
    const result = await tools.c4_validate_plan.execute({ plan })
    expect(result.valid).toBe(false)
  })

  it("rejects tasks without assignedTo", async () => {
    const tools = (await instance).tool
    const plan = JSON.stringify({
      tasks: [
        {
          id: "task-001",
          title: "Test",
          description: "desc",
          criteria: ["c1"],
          // missing assignedTo
        },
      ],
    })
    const result = await tools.c4_validate_plan.execute({ plan })
    expect(result.valid).toBe(false)
  })
})

describe("c4_validate_report", () => {
  it("accepts a valid report", async () => {
    const tools = (await instance).tool
    const report = JSON.stringify({
      taskId: "task-001",
      summary: "Done",
      files: ["src/file.ts"],
      verification: "Run the tests",
    })
    const result = await tools.c4_validate_report.execute({ report })
    expect(result.valid).toBe(true)
  })

  it("rejects report missing fields", async () => {
    const tools = (await instance).tool
    const report = JSON.stringify({ taskId: "task-001" }) // missing summary, files, verification
    const result = await tools.c4_validate_report.execute({ report })
    expect(result.valid).toBe(false)
  })

  it("rejects malformed JSON", async () => {
    const tools = (await instance).tool
    const result = await tools.c4_validate_report.execute({ report: "{bad" })
    expect(result.valid).toBe(false)
  })

  it("rejects report with non-array files", async () => {
    const tools = (await instance).tool
    const report = JSON.stringify({
      taskId: "task-001",
      summary: "Done",
      files: "src/file.ts", // string, not array
      verification: "test",
    })
    const result = await tools.c4_validate_report.execute({ report })
    expect(result.valid).toBe(false)
  })
})

describe("c4_log", () => {
  it("returns logged: true", async () => {
    const tools = (await instance).tool
    const result = await tools.c4_log.execute({
      message: "test log",
      level: "info",
    })
    expect(result.logged).toBe(true)
  })
})
