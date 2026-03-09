#!/usr/bin/env bash
# ╔══════════════════════════════════════════════╗
# ║  C4 — Multi-Agent AI Plugin                  ║
# ║  Universal shell script — works with any     ║
# ║  language/project (Go, Python, Node, etc.)   ║
# ╚══════════════════════════════════════════════╝
#
# Usage:
#   c4 install [<path>]               Install C4 into a folder (default: current dir)
#   ./c4.sh roster
#   ./c4.sh register <slot> <name> <tool>
#   ./c4.sh release <slot>
#   ./c4.sh reset
#   ./c4.sh watch <slot>
#   ./c4.sh done <slot> <task-id> "summary"
#
# Install globally:
#   chmod +x c4.sh && sudo cp c4.sh /usr/local/bin/c4
#   Then: c4 install /path/to/your-project

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
C4_DIR="${C4_DIR:-.c4}"
VALID_SLOTS=("leader" "dev-1" "dev-2" "dev-3")
WATCH_INTERVAL=2   # seconds between queue polls

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m'; DIM='\033[2m'
RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
err()  { echo -e "  ${RED}✗ $*${RESET}" >&2; exit 1; }
info() { echo -e "  ${CYAN}▶${RESET} $*"; }
log()  { # append to events.md
  local agent="$1"; shift
  local msg="$*"
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local agent_upper; agent_upper=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
  local line="[${ts}] [${agent_upper}] ${msg}"
  echo "$line" >> "${C4_DIR}/_log/events.md"
  echo -e "  ${DIM}$(date -u +"%H:%M:%S")${RESET} [${agent}] ${msg}"
}

# ── Guards ────────────────────────────────────────────────────────────────────
require_c4() {
  [[ -d "$C4_DIR" ]] || err "No .c4/ folder found in $(pwd). Are you in the right project?"
}

is_valid_slot() {
  local s="$1"
  for v in "${VALID_SLOTS[@]}"; do [[ "$v" == "$s" ]] && return 0; done
  return 1
}

# ── Frontmatter helpers ───────────────────────────────────────────────────────
# Read a single key from YAML frontmatter
fm_get() {
  local file="$1" key="$2"
  # Extract value between first --- and second ---
  awk '/^---/{f++; next} f==1 && /^'"$key"':/{gsub(/^'"$key"': */, ""); print; exit}' "$file"
}

# Set a key in YAML frontmatter (creates or updates)
fm_set() {
  local file="$1" key="$2" val="$3"
  local tmp; tmp=$(mktemp)

  if grep -q "^${key}:" "$file" 2>/dev/null; then
    # Key exists — update in place
    while IFS= read -r line; do
      if [[ "$line" =~ ^${key}: ]]; then
        echo "${key}: ${val}"
      else
        echo "$line"
      fi
    done < "$file" > "$tmp"
  else
    # Key doesn't exist — insert after first opening ---
    local inserted=0
    local fence_count=0
    while IFS= read -r line; do
      echo "$line"
      if [[ "$line" == "---" && $fence_count -eq 0 ]]; then
        ((fence_count++)) || true
        if [[ $inserted -eq 0 ]]; then
          echo "${key}: ${val}"
          inserted=1
        fi
      fi
    done < "$file" > "$tmp"
  fi

  mv "$tmp" "$file"
}

# Get body (everything after the second ---)
fm_body() {
  local file="$1"
  awk '/^---/{f++; next} f>=2{print}' "$file"
}

# ── cmd: roster ───────────────────────────────────────────────────────────────
cmd_roster() {
  require_c4
  local taken=0

  echo -e "\n${BOLD}👥  C4 Team Roster${RESET}\n"
  printf "  %-10s %-12s %-20s %s\n" "SLOT" "STATUS" "CLAIMED BY" "TOOL"
  echo "  $(printf '%.0s─' {1..55})"

  for slot in "${VALID_SLOTS[@]}"; do
    local profile="${C4_DIR}/${slot}/PROFILE.md"
    local claimed_by tool status icon

    if [[ -f "$profile" ]]; then
      claimed_by=$(fm_get "$profile" "claimed_by")
      tool=$(fm_get "$profile" "tool")
      status=$(fm_get "$profile" "status")
    fi

    claimed_by="${claimed_by:-_empty_}"
    tool="${tool:-}"
    status="${status:-available}"

    if [[ "$claimed_by" == "_empty_" || -z "$claimed_by" ]]; then
      icon="${DIM}⚪${RESET}"; claimed_by="(available)"; tool=""
    else
      icon="${GREEN}🟢${RESET}"; ((taken++)) || true
    fi

    printf "  %b %-10s %-12s %-20s %s\n" "$icon" "$slot" "$status" "$claimed_by" "$tool"
  done

  echo ""
  echo -e "  ${taken}/4 slots filled\n"
}

# ── cmd: register ─────────────────────────────────────────────────────────────
cmd_register() {
  require_c4
  local slot="${1:-}" name="${2:-}" tool="${3:-}"

  [[ -n "$slot" && -n "$name" && -n "$tool" ]] || \
    err "Usage: c4 register <slot> <name> <tool>\n  e.g. c4 register dev-1 \"Claude\" \"Claude Code\""

  is_valid_slot "$slot" || err "Invalid slot: $slot. Choose from: ${VALID_SLOTS[*]}"

  local profile="${C4_DIR}/${slot}/PROFILE.md"
  [[ -f "$profile" ]] || err "PROFILE.md not found: $profile"

  local current; current=$(fm_get "$profile" "claimed_by")
  if [[ -n "$current" && "$current" != "_empty_" ]]; then
    err "Slot '$slot' is already claimed by: $current"
  fi

  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  fm_set "$profile" "claimed_by" "$name"
  fm_set "$profile" "tool"       "$tool"
  fm_set "$profile" "joined_at"  "$ts"
  fm_set "$profile" "status"     "active"

  sync_roster

  log "system" "🎉 ${name} (${tool}) registered as ${slot}"
  echo -e "\n${GREEN}${BOLD}✅  Registered!${RESET}"
  echo -e "   Slot   : ${slot}"
  echo -e "   Name   : ${name}"
  echo -e "   Tool   : ${tool}"
  echo -e "   Joined : ${ts}"
  echo -e "\n   Next: read ${C4_DIR}/${slot}/ROLE.md to get started.\n"
}

# ── cmd: release ──────────────────────────────────────────────────────────────
cmd_release() {
  require_c4
  local slot="${1:-}"
  is_valid_slot "$slot" || err "Usage: c4 release <slot>"

  local profile="${C4_DIR}/${slot}/PROFILE.md"
  fm_set "$profile" "claimed_by" "_empty_"
  fm_set "$profile" "tool"       "_empty_"
  fm_set "$profile" "joined_at"  "~"
  fm_set "$profile" "status"     "available"

  sync_roster
  log "system" "🔓 Slot ${slot} released"
  echo -e "\n${GREEN}✅  Slot '${slot}' is now available.${RESET}\n"
}

# ── cmd: reset ────────────────────────────────────────────────────────────────
cmd_reset() {
  require_c4
  echo -e "\n${YELLOW}🔄  Resetting C4...${RESET}\n"

  # Release all slots
  for slot in "${VALID_SLOTS[@]}"; do
    local profile="${C4_DIR}/${slot}/PROFILE.md"
    if [[ -f "$profile" ]]; then
      fm_set "$profile" "claimed_by" "_empty_"
      fm_set "$profile" "tool"       "_empty_"
      fm_set "$profile" "joined_at"  "~"
      fm_set "$profile" "status"     "available"
    fi
  done
  sync_roster
  ok "All profiles released"

  # Clear dev queues
  for dev in dev-1 dev-2 dev-3; do
    local qdir="${C4_DIR}/${dev}/queue"
    if [[ -d "$qdir" ]]; then
      find "$qdir" -name "*.md" -delete
    fi
  done
  ok "All dev queues cleared"

  # Clear leader inbox/outbox (keep example-*.md files)
  for folder in inbox outbox; do
    local dir="${C4_DIR}/leader/${folder}"
    if [[ -d "$dir" ]]; then
      find "$dir" -name "*.md" ! -name "example-*" -delete
    fi
  done
  ok "Leader inbox & outbox cleared"

  # Reset event log
  cat > "${C4_DIR}/_log/events.md" << 'EOF'
# C4 Event Log

> Append-only. Never delete entries. Format: `[TIMESTAMP] [AGENT] ACTION — details`

---

EOF
  ok "Event log reset"

  log "system" "🔄 Full reset complete"
  echo -e "\n   ${DIM}Ready for a new project. Start with: c4 register${RESET}\n"
}

# ── cmd: watch ────────────────────────────────────────────────────────────────
cmd_watch() {
  require_c4
  local slot="${1:-}"
  is_valid_slot "$slot" || err "Usage: c4 watch <slot>  (slots: ${VALID_SLOTS[*]})"

  if [[ "$slot" == "leader" ]]; then
    watch_leader
  else
    watch_dev "$slot"
  fi
}

watch_leader() {
  local inbox="${C4_DIR}/leader/inbox"
  local seen_file="/tmp/c4_leader_seen_$$"
  touch "$seen_file"

  echo -e "\n${BOLD}🧠  Leader watching inbox...${RESET}"
  echo -e "    Drop a goal.md into ${inbox}/\n"
  echo "$(printf '%.0s─' {1..60})"

  # Also watch for .done.md files
  local done_seen="/tmp/c4_done_seen_$$"
  touch "$done_seen"

  while true; do
    # Check inbox for new goal files
    for f in "${inbox}"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$f" == *"example-"* ]] && continue
      grep -q "^status: processed" "$f" 2>/dev/null && continue
      grep -q "^$f$" "$seen_file" 2>/dev/null && continue

      echo "$f" >> "$seen_file"
      leader_process_goal "$f"
    done

    # Check for new .done.md files in dev queues
    for f in "${C4_DIR}"/dev-*/queue/*.done.md; do
      [[ -f "$f" ]] || continue
      grep -q "^$f$" "$done_seen" 2>/dev/null && continue
      echo "$f" >> "$done_seen"
      leader_review_done "$f"
    done

    sleep "$WATCH_INTERVAL"
  done

  rm -f "$seen_file" "$done_seen"
}

leader_process_goal() {
  local file="$1"
  local filename; filename=$(basename "$file")
  log "leader" "📥 New goal detected: ${filename}"
  log "leader" "🧠 Analyzing goal..."

  # Mark as processing
  fm_set "$file" "status" "processed"

  # Extract bullet point items as tasks
  local tasks=()
  while IFS= read -r line; do
    # Match lines starting with - or * or digit.
    if [[ "$line" =~ ^[[:space:]]*[-\*]\ (.+)$ ]] || [[ "$line" =~ ^[[:space:]]*[0-9]+\.\ (.+)$ ]]; then
      local task_title="${BASH_REMATCH[1]}"
      [[ ${#task_title} -gt 5 ]] && tasks+=("$task_title")
    fi
  done < "$file"

  # Fallback: use goal title as single task
  if [[ ${#tasks[@]} -eq 0 ]]; then
    local title; title=$(grep "^## Goal:" "$file" | sed 's/^## Goal: //')
    tasks+=("${title:-Implement goal}")
  fi

  log "leader" "📋 Created ${#tasks[@]} tasks from goal"

  local devs=("dev-1" "dev-2" "dev-3")
  local i=0
  for task_title in "${tasks[@]}"; do
    local dev="${devs[$((i % 3))]}"
    local task_num; task_num=$(printf "%03d" $((i + 1)))
    local task_id="task-${task_num}"
    local task_file="${C4_DIR}/${dev}/queue/${task_id}.md"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$task_file" << EOF
---
id: ${task_id}
status: pending
assigned_to: ${dev}
created_by: leader
priority: medium
created_at: ${ts}
---

## Task: ${task_title}

### Description
Implement: ${task_title}

### Acceptance Criteria
- [ ] ${task_title} is fully implemented
- [ ] Code is tested and working
EOF

    log "leader" "📤 Routed ${task_id} → ${dev}: ${task_title}"
    ((i++)) || true
  done

  # Move goal to outbox
  local outfile="${C4_DIR}/leader/outbox/$(basename "$file" .md).processed.md"
  mv "$file" "$outfile"
  log "leader" "✅ Goal processed → moved to outbox"
}

leader_review_done() {
  local done_file="$1"
  local dev; dev=$(echo "$done_file" | grep -oE 'dev-[0-9]+')
  local task_id; task_id=$(basename "$done_file" .done.md)
  local queue_dir; queue_dir=$(dirname "$done_file")
  local task_file="${queue_dir}/${task_id}.md"

  log "leader" "🔍 Reviewing: ${dev}/${task_id}.done.md"

  # Simple check: done file has enough content
  local word_count; word_count=$(wc -w < "$done_file")
  if [[ "$word_count" -gt 20 ]]; then
    fm_set "$done_file" "review_status" "approved"
    [[ -f "$task_file" ]] && fm_set "$task_file" "status" "approved"
    log "leader" "✅ APPROVED: ${task_id} by ${dev}"
  else
    local rev_file="${queue_dir}/${task_id}.revision.md"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$rev_file" << EOF
---
task_id: ${task_id}
revision_number: 1
requested_at: ${ts}
requested_by: leader
---

## Revision Request for ${task_id}

### Feedback
The done file appears incomplete. Please provide:
- A detailed summary of what was implemented
- List of files created/modified
- Instructions to verify the work
EOF
    log "leader" "🔄 REVISION requested for ${task_id} → ${dev}"
  fi
}

watch_dev() {
  local slot="$1"
  local queue_dir="${C4_DIR}/${slot}/queue"
  local seen_file="/tmp/c4_${slot}_seen_$$"
  touch "$seen_file"

  # Read agent name from profile
  local agent_name="$slot"
  local profile="${C4_DIR}/${slot}/PROFILE.md"
  if [[ -f "$profile" ]]; then
    local n; n=$(fm_get "$profile" "claimed_by")
    [[ -n "$n" && "$n" != "_empty_" ]] && agent_name="$n"
  fi

  echo -e "\n${BOLD}👀  [${slot}] ${agent_name} is watching for tasks...${RESET}"
  echo -e "    Queue: ${queue_dir}"
  echo -e "    When a task arrives, implement it then run:"
  echo -e "    ${CYAN}→ ./c4.sh done ${slot} <task-id> \"what you did\"${RESET}\n"
  echo "$(printf '%.0s─' {1..60})"

  while true; do
    for f in "${queue_dir}"/task-[0-9][0-9][0-9].md; do
      [[ -f "$f" ]] || continue
      grep -q "^$f$" "$seen_file" 2>/dev/null && continue

      local status; status=$(fm_get "$f" "status")
      local assigned_to; assigned_to=$(fm_get "$f" "assigned_to")

      [[ "$status" == "pending" && "$assigned_to" == "$slot" ]] || {
        echo "$f" >> "$seen_file"
        continue
      }

      echo "$f" >> "$seen_file"

      # Claim the task
      fm_set "$f" "status" "in_progress"
      fm_set "$f" "started_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      local task_id; task_id=$(fm_get "$f" "id")
      log "$slot" "📥 Auto-claimed ${task_id}"

      # Print task to terminal for AI to read
      print_task "$f" "$slot"
    done

    # Check for revision files
    for f in "${queue_dir}"/task-[0-9][0-9][0-9].revision.md; do
      [[ -f "$f" ]] || continue
      local rev_key="rev_${f}"
      grep -q "^${rev_key}$" "$seen_file" 2>/dev/null && continue
      echo "${rev_key}" >> "$seen_file"
      local task_id; task_id=$(fm_get "$f" "task_id")
      print_revision "$f" "$slot" "$task_id"
    done

    sleep "$WATCH_INTERVAL"
  done

  rm -f "$seen_file"
}

print_task() {
  local file="$1" slot="$2"
  local task_id; task_id=$(fm_get "$file" "id")
  local priority; priority=$(fm_get "$file" "priority")
  local body; body=$(fm_body "$file")
  local title; title=$(echo "$body" | grep "^## Task:" | sed 's/^## Task: //')
  local border; border=$(printf '%.0s═' {1..60})

  echo -e "\n${GREEN}╔${border}╗${RESET}"
  local slot_upper; slot_upper=$(echo "$slot" | tr '[:lower:]' '[:upper:]')
  printf "${GREEN}║${RESET}  ${BOLD}🆕 NEW TASK FOR %-44s${GREEN}║${RESET}\n" "${slot_upper}"
  echo -e "${GREEN}╠${border}╣${RESET}"
  printf "${GREEN}║${RESET}  %-58s${GREEN}║${RESET}\n" "ID       : ${task_id}"
  printf "${GREEN}║${RESET}  %-58s${GREEN}║${RESET}\n" "Priority : ${priority:-medium}"
  echo -e "${GREEN}╠${border}╣${RESET}"
  while IFS= read -r line; do
    printf "${GREEN}║${RESET}  %-58s${GREEN}║${RESET}\n" "$line"
  done <<< "$body"
  echo -e "${GREEN}╠${border}╣${RESET}"
  printf "${GREEN}║${RESET}  %-58s${GREEN}║${RESET}\n" "When done, run:"
  printf "${GREEN}║${RESET}  ${CYAN}%-58s${GREEN}║${RESET}\n" "./c4.sh done ${slot} ${task_id} \"your summary\""
  echo -e "${GREEN}╚${border}╝${RESET}\n"
}

print_revision() {
  local file="$1" slot="$2" task_id="$3"
  echo -e "\n${YELLOW}🔄  REVISION REQUEST — ${task_id}${RESET}"
  echo "$(printf '%.0s─' {1..60})"
  fm_body "$file"
  echo "$(printf '%.0s─' {1..60})"
  echo -e "Fix your work then run: ${CYAN}./c4.sh done ${slot} ${task_id} \"revision complete\"${RESET}\n"
}

# ── cmd: done ─────────────────────────────────────────────────────────────────
cmd_done() {
  require_c4
  local slot="${1:-}" task_id="${2:-}"
  shift 2 2>/dev/null || true
  local summary="${*:-Task completed.}"

  [[ -n "$slot" && -n "$task_id" ]] || \
    err "Usage: c4 done <slot> <task-id> \"summary\""

  is_valid_slot "$slot" || err "Invalid slot: $slot"

  local task_file="${C4_DIR}/${slot}/queue/${task_id}.md"
  local done_file="${C4_DIR}/${slot}/queue/${task_id}.done.md"
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  [[ -f "$task_file" ]] || err "Task not found: ${slot}/queue/${task_id}.md"

  local status; status=$(fm_get "$task_file" "status")
  [[ "$status" == "approved" ]] && err "Task ${task_id} is already approved."

  # Update task status
  fm_set "$task_file" "status" "done"
  fm_set "$task_file" "completed_at" "$ts"

  local body; body=$(fm_body "$task_file")
  local title; title=$(echo "$body" | grep "^## Task:" | sed 's/^## Task: //')

  # Write .done.md
  cat > "$done_file" << EOF
---
task_id: ${task_id}
completed_by: ${slot}
completed_at: ${ts}
review_status: pending_review
---

## Done: ${title:-$task_id}

### Summary
${summary}

### Files Modified
*(list the files you created or changed)*

### How to Verify
*(steps to test this works)*
EOF

  log "$slot" "✅ Marked ${task_id} as done"
  echo -e "\n${GREEN}${BOLD}✅  ${task_id} marked as done.${RESET}"
  echo -e "    Leader will review shortly.\n"
}

# ── cmd: install ──────────────────────────────────────────────────────────────
cmd_install() {
  local target="${1:-.}"

  # Resolve to absolute path
  target=$(cd "$target" 2>/dev/null && pwd) || err "Directory not found: ${1}"

  local c4_dir="${target}/.c4"

  if [[ -d "$c4_dir" ]]; then
    echo -e "\n${YELLOW}⚠️   C4 is already installed in: ${target}${RESET}"
    echo -e "    Run ${CYAN}./c4.sh reset${RESET} inside that folder to start fresh.\n"
    exit 1
  fi

  echo -e "\n${BOLD}📦  Installing C4 into: ${target}${RESET}\n"

  # ── Directory structure ────────────────────────────────────────────────────
  mkdir -p \
    "${c4_dir}/leader/inbox" \
    "${c4_dir}/leader/outbox" \
    "${c4_dir}/dev-1/queue" "${c4_dir}/dev-1/workspace" \
    "${c4_dir}/dev-2/queue" "${c4_dir}/dev-2/workspace" \
    "${c4_dir}/dev-3/queue" "${c4_dir}/dev-3/workspace" \
    "${c4_dir}/_log"
  ok "Created .c4/ directory structure"

  # ── Copy c4.sh itself ──────────────────────────────────────────────────────
  local script_src; script_src=$(realpath "${BASH_SOURCE[0]}")
  cp "$script_src" "${target}/c4.sh"
  chmod +x "${target}/c4.sh"
  ok "Copied c4.sh → ${target}/c4.sh"

  # ── AGENTS.md ─────────────────────────────────────────────────────────────
  cat > "${c4_dir}/AGENTS.md" << 'AGENTS_EOF'
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
AGENTS_EOF

  # ── c4.config.md ──────────────────────────────────────────────────────────
  cat > "${c4_dir}/c4.config.md" << 'CONFIG_EOF'
# C4 Config

---
project_name: my-project
leader_model: claude-sonnet
dev_model: claude-haiku
num_devs: 3
max_concurrent_tasks_per_dev: 1
auto_review: true
log_level: info
---

## Notes

- `leader_model`: AI model used for the Leader agent
- `dev_model`: AI model used for each Developer agent
- `num_devs`: Number of developer agents (1–5)
- `max_concurrent_tasks_per_dev`: How many tasks a dev can hold at once
- `auto_review`: If true, Leader auto-reviews `.done.md` files when they appear
CONFIG_EOF

  # ── roster.md ─────────────────────────────────────────────────────────────
  cat > "${c4_dir}/roster.md" << 'ROSTER_EOF'
# C4 Team Roster

> This is the **self-registration board**. When you (an AI agent) join this project, your first action is to:
> 1. Pick an available slot below
> 2. Edit this file — replace `_empty_` with your name/identity
> 3. Read your assigned `ROLE.md` and start working

---

## 🪑 Available Slots

| Slot | Role | Claimed By | Tool | Joined At |
| --- | --- | --- | --- | --- |
| `leader` | 🧠 Leader — breaks goals into tasks, reviews results | _empty_ | _empty_ | — |
| `dev-1` | 💻 Dev-1 — Backend specialist (APIs, auth, DB) | _empty_ | _empty_ | — |
| `dev-2` | 🎨 Dev-2 — Frontend specialist (UI, components) | _empty_ | _empty_ | — |
| `dev-3` | 🔧 Dev-3 — DevOps/Test specialist (CI, testing) | _empty_ | _empty_ | — |

---

## 📋 How to Register

1. **Look at the table above** — find a slot where `Claimed By` is `_empty_`
2. **Edit this file** — fill in:
   - `Claimed By`: your name (e.g. `Claude`, `Copilot`, `GPT-4`)
   - `Tool`: the AI tool you're running in (e.g. `Claude Code`, `GitHub Copilot`, `Cursor`)
   - `Joined At`: current timestamp (ISO 8601)
3. **Confirm** by saying: *"I've registered as [slot]. Ready."*
4. **Read your ROLE.md**: `.c4/[slot]/ROLE.md`

> ⚠️ If all slots are taken, wait for a slot to free up or ask the human to reset a slot.

---

## 📖 Role Summaries

### 🧠 Leader (`leader`)
You are the **project manager**. The human will talk to you directly to set goals.
- Watch `.c4/leader/inbox/` for `goal.md` files
- Break the goal into tasks → route to dev queues
- Review `.done.md` files when devs finish
- **Start here**: read `.c4/leader/ROLE.md`

### 💻 Dev-1 (`dev-1`) — Backend
- Watch `.c4/dev-1/queue/` for task files
- Implement backend features: APIs, auth, database
- **Start here**: read `.c4/dev-1/ROLE.md`

### 🎨 Dev-2 (`dev-2`) — Frontend
- Watch `.c4/dev-2/queue/` for task files
- Implement frontend features: UI, components, styles
- **Start here**: read `.c4/dev-2/ROLE.md`

### 🔧 Dev-3 (`dev-3`) — DevOps/Test
- Watch `.c4/dev-3/queue/` for task files
- Write tests, set up CI/CD, handle infrastructure
- **Start here**: read `.c4/dev-3/ROLE.md`
ROSTER_EOF

  # ── events.md ─────────────────────────────────────────────────────────────
  cat > "${c4_dir}/_log/events.md" << 'EVENTS_EOF'
# C4 Event Log

> Append-only. Never delete entries. Format: `[TIMESTAMP] [AGENT] ACTION — details`

---

EVENTS_EOF

  # ── leader/ROLE.md ────────────────────────────────────────────────────────
  cat > "${c4_dir}/leader/ROLE.md" << 'LEADER_ROLE_EOF'
# Leader Agent — ROLE.md

## Identity
You are the **Leader AI** of the C4 system.

## Responsibilities

### 1. Inbox Watching (`leader/inbox/`)
When a new `goal.md` (or any `.md` file) appears in `leader/inbox/`:
- Read and fully understand the goal
- Break it into clear, atomic tasks (one task = one dev can complete it independently)
- Assign each task to a developer (round-robin: dev-1, dev-2, dev-3)
- Write each task as `task-XXX.md` into the correct `dev-X/queue/` folder
- Log the plan to `_log/events.md`
- Move the processed goal to `leader/outbox/goal.processed.md`

### 2. Review Watching (`dev-*/queue/*.done.md`)
When a `task-XXX.done.md` appears:
- Read the original `task-XXX.md` and the `.done.md` result
- Verify all acceptance criteria are met
- If **approved**: append `status: approved` to the done file, log to `_log/events.md`
- If **needs changes**: write `task-XXX.revision.md` in the same queue folder with specific feedback

## Task Naming
- Tasks are numbered sequentially: `task-001.md`, `task-002.md`, etc.
- Always zero-pad to 3 digits

## Task Distribution Strategy
- Assign tasks evenly across dev-1, dev-2, dev-3
- Consider task complexity — heavier tasks to dev-1, lighter to dev-3
- Never assign more than `max_concurrent_tasks_per_dev` tasks per dev at once

## Communication Style
- Be specific and actionable in task descriptions
- Include acceptance criteria in every task
- When reviewing, give concrete, constructive feedback
LEADER_ROLE_EOF

  # ── leader/PROFILE.md ─────────────────────────────────────────────────────
  cat > "${c4_dir}/leader/PROFILE.md" << 'LEADER_PROFILE_EOF'
---
type: registration
slot: leader
claimed_by: _empty_
tool: _empty_
joined_at: ~
status: available
---

# Leader Agent Profile

Fill in your details below when you claim this slot.

## Identity
- **Name / Handle**: _fill in your name_
- **AI Tool**: _e.g. Claude Code, GitHub Copilot, Cursor_
- **Instance**: _optional — e.g. "claude-sonnet-4.5"_

## Responsibilities
- Break down goals from `.c4/leader/inbox/` into tasks
- Route tasks to dev-1, dev-2, dev-3 queues
- Review `.done.md` files and approve or request revision
- Be the human's primary contact for goal-setting

## How to Claim
Edit the frontmatter above:
- `claimed_by:` → your name
- `tool:` → your AI tool
- `joined_at:` → current ISO timestamp
- `status:` → `active`

Then read your full ROLE.md: `.c4/leader/ROLE.md`
LEADER_PROFILE_EOF

  # ── dev-1/ROLE.md ─────────────────────────────────────────────────────────
  cat > "${c4_dir}/dev-1/ROLE.md" << 'DEV1_ROLE_EOF'
# Dev-1 Agent — ROLE.md

## Identity
You are **Developer AI #1** of the C4 system.
You are a **senior full-stack developer** with expertise in backend systems and APIs.

## Responsibilities

### Queue Watching (`dev-1/queue/`)
When a new `task-XXX.md` appears in your queue:
1. Read the task carefully
2. Update `status: in_progress` in the task frontmatter
3. Log start to `_log/events.md`
4. Implement the task — write actual code, make real changes to the project
5. Verify all acceptance criteria are met
6. Create `task-XXX.done.md` with:
   - Summary of what was done
   - Files created/modified
   - How to verify the work
7. Update original task `status: done`
8. Log completion to `_log/events.md`

### Revision Watching (`dev-1/queue/*.revision.md`)
When a `task-XXX.revision.md` appears:
- Read the Leader's feedback carefully
- Address every point raised
- Update your `task-XXX.done.md` with the changes
- Create a new `task-XXX.done-v2.md` (increment version each time)

## Working Rules
- Work only on tasks assigned to `dev-1`
- Use `dev-1/workspace/` as your scratchpad for notes and drafts
- Always write real, working code — no placeholders
- If a task is unclear or blocked, set `status: blocked` and create `task-XXX.blocked.md`

## Specialization
- Backend APIs, database design, authentication, infrastructure
DEV1_ROLE_EOF

  # ── dev-1/PROFILE.md ──────────────────────────────────────────────────────
  cat > "${c4_dir}/dev-1/PROFILE.md" << 'DEV1_PROFILE_EOF'
---
type: registration
slot: dev-1
claimed_by: _empty_
tool: _empty_
joined_at: ~
status: available
specialization: backend
---

# Dev-1 Agent Profile

Fill in your details below when you claim this slot.

## Identity
- **Name / Handle**: _fill in your name_
- **AI Tool**: _e.g. Claude Code, GitHub Copilot, Cursor_
- **Instance**: _optional_

## Specialization
Backend development: REST APIs, authentication, database design, server logic.

## How to Claim
Edit the frontmatter above:
- `claimed_by:` → your name
- `tool:` → your AI tool
- `joined_at:` → current ISO timestamp
- `status:` → `active`

Then read your full ROLE.md: `.c4/dev-1/ROLE.md`
DEV1_PROFILE_EOF

  # ── dev-2/ROLE.md ─────────────────────────────────────────────────────────
  cat > "${c4_dir}/dev-2/ROLE.md" << 'DEV2_ROLE_EOF'
# Dev-2 Agent — ROLE.md

## Identity
You are **Developer AI #2** of the C4 system.
You are a **senior frontend developer** with expertise in UI, UX, and component design.

## Responsibilities

### Queue Watching (`dev-2/queue/`)
When a new `task-XXX.md` appears in your queue:
1. Read the task carefully
2. Update `status: in_progress` in the task frontmatter
3. Log start to `_log/events.md`
4. Implement the task — write actual code, make real changes to the project
5. Verify all acceptance criteria are met
6. Create `task-XXX.done.md` with:
   - Summary of what was done
   - Files created/modified
   - How to verify the work
7. Update original task `status: done`
8. Log completion to `_log/events.md`

### Revision Watching (`dev-2/queue/*.revision.md`)
When a `task-XXX.revision.md` appears:
- Read the Leader's feedback carefully
- Address every point raised
- Create a new `task-XXX.done-v2.md` (increment version each time)

## Working Rules
- Work only on tasks assigned to `dev-2`
- Use `dev-2/workspace/` as your scratchpad for notes and drafts
- Always write real, working code — no placeholders
- If a task is unclear or blocked, set `status: blocked` and create `task-XXX.blocked.md`

## Specialization
- Frontend React/Vue/Next.js, CSS, component libraries, accessibility, animations
DEV2_ROLE_EOF

  # ── dev-2/PROFILE.md ──────────────────────────────────────────────────────
  cat > "${c4_dir}/dev-2/PROFILE.md" << 'DEV2_PROFILE_EOF'
---
type: registration
slot: dev-2
claimed_by: _empty_
tool: _empty_
joined_at: ~
status: available
specialization: frontend
---

# Dev-2 Agent Profile

Fill in your details below when you claim this slot.

## Identity
- **Name / Handle**: _fill in your name_
- **AI Tool**: _e.g. Claude Code, GitHub Copilot, Cursor_
- **Instance**: _optional_

## Specialization
Frontend development: React/Vue/Next.js, UI components, CSS, accessibility, animations.

## How to Claim
Edit the frontmatter above:
- `claimed_by:` → your name
- `tool:` → your AI tool
- `joined_at:` → current ISO timestamp
- `status:` → `active`

Then read your full ROLE.md: `.c4/dev-2/ROLE.md`
DEV2_PROFILE_EOF

  # ── dev-3/ROLE.md ─────────────────────────────────────────────────────────
  cat > "${c4_dir}/dev-3/ROLE.md" << 'DEV3_ROLE_EOF'
# Dev-3 Agent — ROLE.md

## Identity
You are **Developer AI #3** of the C4 system.
You are a **senior DevOps / testing engineer** with expertise in CI/CD, testing, and reliability.

## Responsibilities

### Queue Watching (`dev-3/queue/`)
When a new `task-XXX.md` appears in your queue:
1. Read the task carefully
2. Update `status: in_progress` in the task frontmatter
3. Log start to `_log/events.md`
4. Implement the task — write actual code, make real changes to the project
5. Verify all acceptance criteria are met
6. Create `task-XXX.done.md` with:
   - Summary of what was done
   - Files created/modified
   - How to verify the work
7. Update original task `status: done`
8. Log completion to `_log/events.md`

### Revision Watching (`dev-3/queue/*.revision.md`)
When a `task-XXX.revision.md` appears:
- Read the Leader's feedback carefully
- Address every point raised
- Create a new `task-XXX.done-v2.md` (increment version each time)

## Working Rules
- Work only on tasks assigned to `dev-3`
- Use `dev-3/workspace/` as your scratchpad for notes and drafts
- Always write real, working code — no placeholders
- If a task is unclear or blocked, set `status: blocked` and create `task-XXX.blocked.md`

## Specialization
- Testing (unit, integration, e2e), CI/CD pipelines, Docker, monitoring, performance
DEV3_ROLE_EOF

  # ── dev-3/PROFILE.md ──────────────────────────────────────────────────────
  cat > "${c4_dir}/dev-3/PROFILE.md" << 'DEV3_PROFILE_EOF'
---
type: registration
slot: dev-3
claimed_by: _empty_
tool: _empty_
joined_at: ~
status: available
specialization: devops-testing
---

# Dev-3 Agent Profile

Fill in your details below when you claim this slot.

## Identity
- **Name / Handle**: _fill in your name_
- **AI Tool**: _e.g. Claude Code, GitHub Copilot, Cursor_
- **Instance**: _optional_

## Specialization
DevOps & Testing: unit/integration/e2e tests, CI/CD pipelines, Docker, monitoring, performance.

## How to Claim
Edit the frontmatter above:
- `claimed_by:` → your name
- `tool:` → your AI tool
- `joined_at:` → current ISO timestamp
- `status:` → `active`

Then read your full ROLE.md: `.c4/dev-3/ROLE.md`
DEV3_PROFILE_EOF

  ok "Wrote all template files"

  echo -e "\n${GREEN}${BOLD}✅  C4 installed successfully!${RESET}"
  echo -e "   Folder : ${target}"
  echo -e "\n   ${BOLD}Next steps:${RESET}"
  echo -e "   ${CYAN}cd ${target}${RESET}"
  echo -e "   ${CYAN}./c4.sh register leader \"Claude\" \"Claude Code\"${RESET}"
  echo -e "   ${CYAN}./c4.sh register dev-1  \"Copilot\" \"GitHub Copilot\"${RESET}"
  echo -e "   ${CYAN}./c4.sh watch leader${RESET}   ${DIM}# in a terminal${RESET}"
  echo -e "   ${CYAN}./c4.sh watch dev-1${RESET}    ${DIM}# in another terminal${RESET}\n"
}

# ── cmd: init ─────────────────────────────────────────────────────────────────
cmd_init() {
  local slot="${1:-}"
  
  [[ -n "$slot" ]] || err "Usage: c4 init <slot>  (slots: ${VALID_SLOTS[*]})"
  is_valid_slot "$slot" || err "Invalid slot: $slot. Choose from: ${VALID_SLOTS[*]}"
  
  local role_file="${C4_DIR}/${slot}/ROLE.md"
  local profile_file="${C4_DIR}/${slot}/PROFILE.md"
  
  [[ -f "$role_file" ]] || err "ROLE.md not found: $role_file"
  
  local role_content; role_content=$(cat "$role_file")
  local profile_content; profile_content=$(cat "$profile_file")
  
  echo -e "
${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}
${CYAN}║  C4 AGENT INITIALIZATION — ${slot}${RESET}$(printf ' %.0s' {1..30})${CYAN}║${RESET}
${CYAN}╚════════════════════════════════════════════════════════════════╝${RESET}

${YELLOW}📋 COPY THE CONTENT BELOW AND PASTE INTO YOUR AI ASSISTANT:${RESET}

---

# C4 Agent — ${slot}

> When you read this, you are now acting as the **${slot}** agent in the C4 multi-agent system.

## 📂 Your Profile
${profile_content}

## 📜 Your Role Rules
${role_content}

---

${YELLOW}📋 VERIFICATION:${RESET}
After reading this, respond with: \"I've registered as ${slot}. Ready.\"

${GREEN}✅ END OF PROMPT — COPY EVERYTHING ABOVE${RESET}
"
}

# ── cmd: help ─────────────────────────────────────────────────────────────────
cmd_help() {
  echo -e "
${BOLD}C4 — Multi-Agent AI Plugin${RESET}
${DIM}Works with any project: Go, Python, Node, Rust, etc.${RESET}

${BOLD}Commands:${RESET}
  ${CYAN}c4 install [<path>]${RESET}                    Install C4 into a folder (default: current dir)
  ${CYAN}c4 roster${RESET}                              Show team roster
  ${CYAN}c4 register <slot> <name> <tool>${RESET}       Claim a role slot
  ${CYAN}c4 init <slot>${RESET}                         Output role prompt (copy to AI assistant)
  ${CYAN}c4 release <slot>${RESET}                      Free up a slot
  ${CYAN}c4 reset${RESET}                               Clear everything, start fresh
  ${CYAN}c4 watch <slot>${RESET}                        Watch & auto-receive tasks
  ${CYAN}c4 done <slot> <task-id> \"summary\"${RESET}    Mark a task as completed

${BOLD}Slots:${RESET} leader, dev-1, dev-2, dev-3

${BOLD}Quick Start:${RESET}
  sudo cp c4.sh /usr/local/bin/c4
  c4 install ~/my-project
  cd ~/my-project
  ./c4.sh register leader \"Claude\" \"Claude Code\"
  ./c4.sh watch dev-1

${BOLD}Examples:${RESET}
  ./c4.sh init leader                           # Output leader prompt to copy
  ./c4.sh init dev-1                           # Output dev-1 prompt to copy
  ./c4.sh register leader \"Claude\" \"Claude Code\"
  ./c4.sh register dev-1  \"Copilot\" \"GitHub Copilot\"
  ./c4.sh watch dev-1
  ./c4.sh done dev-1 task-003 \"added GET /count route in main.go\"
  ./c4.sh roster
  ./c4.sh reset
"
}

# ── Sync roster.md table ──────────────────────────────────────────────────────
sync_roster() {
  local roster_file="${C4_DIR}/roster.md"
  [[ -f "$roster_file" ]] || return

  local role_labels=(
    "leader|🧠 Leader — breaks goals into tasks, reviews results"
    "dev-1|💻 Dev-1 — Backend specialist (APIs, auth, DB)"
    "dev-2|🎨 Dev-2 — Frontend specialist (UI, components)"
    "dev-3|🔧 Dev-3 — DevOps/Test specialist (CI, testing)"
  )

  # Write new table to temp file
  local tmp_table; tmp_table=$(mktemp)
  echo "| Slot | Role | Claimed By | Tool | Joined At |" >> "$tmp_table"
  echo "| --- | --- | --- | --- | --- |" >> "$tmp_table"

  for entry in "${role_labels[@]}"; do
    local slot="${entry%%|*}"
    local role="${entry##*|}"
    local profile="${C4_DIR}/${slot}/PROFILE.md"
    local claimed_by="" tool="" joined_at=""

    if [[ -f "$profile" ]]; then
      claimed_by=$(fm_get "$profile" "claimed_by")
      tool=$(fm_get "$profile" "tool")
      joined_at=$(fm_get "$profile" "joined_at")
    fi

    claimed_by="${claimed_by:-_empty_}"
    tool="${tool:-_empty_}"

    if [[ "$claimed_by" == "_empty_" ]]; then
      echo "| \`${slot}\` | ${role} | _empty_ | _empty_ | — |" >> "$tmp_table"
    else
      echo "| \`${slot}\` | ${role} | **${claimed_by}** | ${tool} | ${joined_at:0:19} |" >> "$tmp_table"
    fi
  done

  # Replace table block in roster.md: skip old table lines, insert new ones
  local tmp_out; tmp_out=$(mktemp)
  local in_table=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^\|\ Slot\ \| ]]; then
      in_table=1
      cat "$tmp_table" >> "$tmp_out"
      continue
    fi
    if [[ $in_table -eq 1 ]]; then
      [[ "$line" =~ ^\| ]] && continue   # skip old table rows
      in_table=0
    fi
    echo "$line" >> "$tmp_out"
  done < "$roster_file"

  mv "$tmp_out" "$roster_file"
  rm -f "$tmp_table"
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
  install)  cmd_install "$@" ;;
  roster)   cmd_roster ;;
  register) cmd_register "$@" ;;
  release)  cmd_release "$@" ;;
  reset)    cmd_reset ;;
  init)     cmd_init "$@" ;;
  watch)    cmd_watch "$@" ;;
  done)     cmd_done "$@" ;;
  help|--help|-h) cmd_help ;;
  *) echo -e "${RED}Unknown command: ${CMD}${RESET}"; cmd_help; exit 1 ;;
esac
