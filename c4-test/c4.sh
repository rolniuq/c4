#!/usr/bin/env bash
# ╔══════════════════════════════════════════════╗
# ║  C4 — Multi-Agent AI Plugin                  ║
# ║  Universal shell script — works with any     ║
# ║  language/project (Go, Python, Node, etc.)   ║
# ╚══════════════════════════════════════════════╝
#
# Usage:
#   ./c4.sh roster
#   ./c4.sh register <slot> <name> <tool>
#   ./c4.sh release <slot>
#   ./c4.sh reset
#   ./c4.sh watch <slot>
#   ./c4.sh done <slot> <task-id> "summary"
#
# Install globally (optional):
#   chmod +x c4.sh && sudo cp c4.sh /usr/local/bin/c4

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

# ── cmd: help ─────────────────────────────────────────────────────────────────
cmd_help() {
  echo -e "
${BOLD}C4 — Multi-Agent AI Plugin${RESET}
${DIM}Works with any project: Go, Python, Node, Rust, etc.${RESET}

${BOLD}Commands:${RESET}
  ${CYAN}c4 roster${RESET}                              Show team roster
  ${CYAN}c4 register <slot> <name> <tool>${RESET}       Claim a role slot
  ${CYAN}c4 release <slot>${RESET}                      Free up a slot
  ${CYAN}c4 reset${RESET}                               Clear everything, start fresh
  ${CYAN}c4 watch <slot>${RESET}                        Watch & auto-receive tasks
  ${CYAN}c4 done <slot> <task-id> \"summary\"${RESET}    Mark a task as completed

${BOLD}Slots:${RESET} leader, dev-1, dev-2, dev-3

${BOLD}Examples:${RESET}
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
  roster)   cmd_roster ;;
  register) cmd_register "$@" ;;
  release)  cmd_release "$@" ;;
  reset)    cmd_reset ;;
  watch)    cmd_watch "$@" ;;
  done)     cmd_done "$@" ;;
  help|--help|-h) cmd_help ;;
  *) echo -e "${RED}Unknown command: ${CMD}${RESET}"; cmd_help; exit 1 ;;
esac
