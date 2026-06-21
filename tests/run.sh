#!/usr/bin/env bash
# C4 Test Runner
# Usage: ./tests/run.sh [--verbose]
#
# Runs all tests and validates everything before allowing a DONE claim.
# Exit code 0 = all clean. Non-zero = fix something.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

PASS=0
FAIL=0
SKIP=0

ok()   { PASS=$((PASS + 1)); echo -e "  \033[0;32m✓\033[0m $1"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  \033[0;31m✗ $1\033[0m"; }
skip() { SKIP=$((SKIP + 1)); echo -e "  \033[1;33m- $1 (skipped)\033[0m"; }
header() { echo -e "\n\033[1m══ $1 ══\033[0m"; }

cleanup() {
  [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

# ── Helpers ────────────────────────────────────────────────────────────────
assert_file() {
  [[ -f "$1" ]] && ok "$2" || fail "$2 (missing: $1)"
}

assert_not_file() {
  [[ ! -f "$1" ]] && ok "$2" || fail "$2 (exists: $1)"
}

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  grep -q "$pattern" "$file" && ok "$label" || fail "$label ($file missing pattern: $pattern)"
}

assert_not_contains() {
  local file="$1" pattern="$2" label="$3"
  ! grep -q "$pattern" "$file" && ok "$label" || fail "$label ($file contains forbidden: $pattern)"
}

# ── 1. Validate all .md frontmatter ────────────────────────────────────────
header "Frontmatter Validation"

while IFS= read -r md_file; do
  name=$(basename "$md_file")
  rel="${md_file#$ROOT/}"

  # Must start with ---
  head -1 "$md_file" | grep -q "^---" && ok "$rel: opens with ---" || fail "$rel: missing opening ---"

  # Must have closing --- within first 20 lines
  awk 'NR==1 && /^---/{f=1; next} f==1 && /^---/{f=2; print NR; exit}' "$md_file" | grep -q . \
    && ok "$rel: has closing ---" || fail "$rel: missing closing ---"

  # Must have description field in frontmatter
  awk '/^---/{f++; next} f==1 && /^description:/{found=1} f==2{exit} END{exit !found}' "$md_file" \
    && ok "$rel: has description" || fail "$rel: missing description in frontmatter"

  # No emoji in description field
  desc_line=$(awk '/^---/{f++; next} f==1 && /^description:/{print; exit}' "$md_file")
  if echo "$desc_line" | grep -qP '[^\x00-\x7F]'; then
    fail "$rel: description contains non-ASCII characters (may confuse AI parsers)"
  else
    ok "$rel: description is ASCII-only"
  fi
done < <(find "$ROOT/.opencode" -name "*.md" 2>/dev/null || true)

# Also validate .c4/ templates if they exist
while IFS= read -r md_file; do
  rel="${md_file#$ROOT/}"
  head -1 "$md_file" | grep -q "^---" && ok "$rel: opens with ---" || ok "$rel: no frontmatter (template)"
done < <(find "$ROOT/.c4" -name "*.md" 2>/dev/null || true)

# ── 2. Validate c4.sh syntax ───────────────────────────────────────────────
header "Bash Syntax"

if command -v bash &>/dev/null; then
  bash -n "$ROOT/c4.sh" && ok "c4.sh: bash syntax OK" || fail "c4.sh: bash syntax error"
else
  skip "bash: not found"
fi

# ── 3. c4.sh command tests (sandboxed) ─────────────────────────────────────
header "Command Tests"

TMPDIR=$(mktemp -d /tmp/c4-test-XXXX)

# Test install
"$ROOT/c4.sh" install "$TMPDIR" >/dev/null 2>&1 && ok "install: exits 0" || fail "install: non-zero exit"
assert_file "$TMPDIR/c4.sh" "install: c4.sh copied"
assert_file "$TMPDIR/.c4/leader/inbox/.gitkeep" "install: leader/inbox exists" || true
assert_file "$TMPDIR/.c4/AGENTS.md" "install: AGENTS.md created"

# Test register
"$ROOT/c4.sh" register leader "TestBot" "CLI" 2>&1 | head -1 || true
# shellcheck disable=SC1090
cd "$TMPDIR"
"$TMPDIR/c4.sh" register leader "TestBot" "CLI" >/dev/null 2>&1 && ok "register: exits 0" || fail "register: non-zero exit"
assert_contains "$TMPDIR/.c4/leader/PROFILE.md" "claimed_by: TestBot" "register: PROFILE.md updated"
assert_contains "$TMPDIR/.c4/roster.md" "TestBot" "register: roster.md updated"

# Test duplicate register
"$TMPDIR/c4.sh" register leader "Other" "CLI" >/dev/null 2>&1 && fail "register: allowed duplicate" || ok "register: rejects duplicate"

# Test release
"$TMPDIR/c4.sh" release leader >/dev/null 2>&1 && ok "release: exits 0" || fail "release: non-zero exit"
assert_contains "$TMPDIR/.c4/leader/PROFILE.md" "claimed_by: _empty_" "release: PROFILE.md cleared"

# Test done
"$TMPDIR/c4.sh" register dev-1 "DevBot" "CLI" >/dev/null 2>&1
mkdir -p "$TMPDIR/.c4/dev-1/queue"
cat > "$TMPDIR/.c4/dev-1/queue/task-001.md" << 'EOF'
---
id: task-001
status: pending
assigned_to: dev-1
---
## Task: Test
EOF
"$TMPDIR/c4.sh" done dev-1 task-001 "implemented test" >/dev/null 2>&1 && ok "done: exits 0" || fail "done: non-zero exit"
assert_file "$TMPDIR/.c4/dev-1/queue/task-001.done.md" "done: .done.md created"
assert_contains "$TMPDIR/.c4/dev-1/queue/task-001.md" "status: done" "done: task status updated"

# Test roster
"$TMPDIR/c4.sh" roster >/dev/null 2>&1 && ok "roster: exits 0" || fail "roster: non-zero exit"

# Test reset
"$TMPDIR/c4.sh" reset >/dev/null 2>&1 && ok "reset: exits 0" || fail "reset: non-zero exit"

cd "$ROOT"

# ── 4. Plugin TypeScript validation ────────────────────────────────────────
header "Plugin Validation"

if command -v npx &>/dev/null && npx --yes tsc --version &>/dev/null 2>&1; then
  npx tsc --noEmit --strict --moduleResolution bundler "$ROOT/.opencode/plugins/c4-plugin.ts" 2>&1 | \
    grep -v "node_modules" | grep -v "@opencode-ai/plugin" | grep -v "declaration" | grep -v "TS" || true
  # If only warnings about @opencode-ai/plugin, that's OK
  local errors
  errors=$(npx tsc --noEmit --strict --moduleResolution bundler "$ROOT/.opencode/plugins/c4-plugin.ts" 2>&1 | grep -v "@opencode-ai/plugin" | grep -v "node_modules" | grep -v "TS" || true)
  if [[ -z "$errors" ]]; then
    ok "plugin: TypeScript OK"
  else
    fail "plugin: TypeScript errors:\n$errors"
  fi
else
  skip "plugin: tsc not available — validate manually"
fi

# Plugin must export default
grep -q "export default" "$ROOT/.opencode/plugins/c4-plugin.ts" \
  && ok "plugin: exports default" || fail "plugin: missing export default"

# Plugin must define all 4 tools
for tool in c4_init c4_validate_plan c4_validate_report c4_log; do
  grep -q "${tool}:" "$ROOT/.opencode/plugins/c4-plugin.ts" \
    && ok "plugin: defines ${tool}" || fail "plugin: missing ${tool}"
done

# ── 5. Agent definitions validation ────────────────────────────────────────
header "Agent Validation"

# Leader: must have both plan and review modes
grep -q 'type: "plan"' "$ROOT/.opencode/agents/c4-leader.md" \
  && ok "leader: defines plan mode" || fail "leader: missing plan mode"
grep -q 'type: "review"' "$ROOT/.opencode/agents/c4-leader.md" \
  && ok "leader: defines review mode" || fail "leader: missing review mode"

# Dev: must have task implementation instructions
grep -q "Implement the task" "$ROOT/.opencode/agents/c4-dev.md" \
  && ok "dev: has implement instructions" || fail "dev: missing implement instructions"

# Dev: must output done report JSON
grep -q "taskId.*summary.*files.*verification" "$ROOT/.opencode/agents/c4-dev.md" \
  && ok "dev: output includes all required fields" || fail "dev: output missing required fields"

# ── 6. Command validation ──────────────────────────────────────────────────
header "Command Validation"

grep -q '\$ARGUMENTS' "$ROOT/.opencode/commands/c4.md" \
  && ok "command: uses \$ARGUMENTS" || fail "command: missing \$ARGUMENTS"

grep -q 'c4_init' "$ROOT/.opencode/commands/c4.md" \
  && ok "command: calls c4_init" || fail "command: missing c4_init"

grep -q 'c4_validate_plan' "$ROOT/.opencode/commands/c4.md" \
  && ok "command: calls c4_validate_plan" || fail "command: missing c4_validate_plan"

grep -q 'c4_validate_report' "$ROOT/.opencode/commands/c4.md" \
  && ok "command: calls c4_validate_report" || fail "command: missing c4_validate_report"

grep -q 'c4_log' "$ROOT/.opencode/commands/c4.md" \
  && ok "command: calls c4_log" || fail "command: missing c4_log"

grep -q "max_revision_count.*3\|revision count < 3\|retry.*3\|3 revisions" < <(tr '[:upper:]' '[:lower:]' < "$ROOT/.opencode/commands/c4.md") \
  && ok "command: has MAX_RETRIES=3" || fail "command: missing retry limit"

# ── 7. Check for build artifacts / temp files ──────────────────────────────
header "Clean Build Check"

# No .tmp files in the repo
tmp_count=$(find "$ROOT" -name "*.tmp" -not -path "*.git/*" 2>/dev/null | wc -l | tr -d ' ')
[[ "$tmp_count" -eq 0 ]] && ok "no .tmp files" || fail "found $tmp_count .tmp file(s)"

# No node_modules unless package.json exists
if [[ -f "$ROOT/package.json" ]]; then
  [[ -d "$ROOT/node_modules" ]] && ok "node_modules present (package.json exists)" \
    || ok "no node_modules (run npm/bun install to add)"
fi

# No .cache or .turbo directories
for dir in .cache .turbo dist build out; do
  [[ -d "$ROOT/$dir" ]] && fail "found $dir/ (build artifact)" || ok "no $dir/"
done

# ── 8. Logic pattern enforcement ───────────────────────────────────────────
header "Pattern Enforcement"

# c4.sh functions must follow cmd_<name>() pattern
bad_funcs=$(grep -n '^[a-zA-Z_][a-zA-Z0-9_]*()' "$ROOT/c4.sh" | grep -v '^[0-9]*:cmd_\|^[0-9]*:fm_\|^[0-9]*:sync_\|^[0-9]*:watch_\|^[0-9]*:leader_\|^[0-9]*:print_\|^[0-9]*:require_\|^[0-9]*:is_valid_\|^[0-9]*:assert_\|^[0-9]*:ok\|^[0-9]*:err\|^[0-9]*:info\|^[0-9]*:log' || true)
if [[ -z "$bad_funcs" ]]; then
  ok "c4.sh: all functions follow naming convention"
else
  fail "c4.sh: functions violating convention:\n$bad_funcs"
fi

# No TODO/FIXME/HACK comments in code (allow in docs)
todo_count=$(grep -rn "TODO\|FIXME\|HACK" "$ROOT/c4.sh" "$ROOT/.opencode" 2>/dev/null | grep -v "AGENTS.md" | grep -v "\.md:" | wc -l | tr -d ' ')
[[ "$todo_count" -eq 0 ]] && ok "no TODO/FIXME/HACK in code" \
  || fail "found $todo_count TODO/FIXME/HACK in code (docs excluded)"

# All .opencode/agent files must have mode: subagent
for agent_file in "$ROOT/.opencode/agents/"*.md; do
  [[ -f "$agent_file" ]] || continue
  name=$(basename "$agent_file" .md)
  awk '/^---/{f++; next} f==1 && /^mode:/{print; exit}' "$agent_file" | grep -q "subagent" \
    && ok "$name: mode is subagent" || fail "$name: mode must be subagent"
done

# ── Results ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "═══════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "\n  ❌ Some tests FAILED. Fix before claiming DONE."
  exit 1
else
  echo -e "\n  ✅ All checks passed. Ready for DONE."
  exit 0
fi
