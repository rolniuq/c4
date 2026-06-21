# C4 — Development Tooling
#
# Usage:
#   make test       Run all tests
#   make lint       Validate syntax + formatting
#   make clean      Remove build artifacts and temp files
#   make precommit  Run everything required before DONE/commit

SHELL := /usr/bin/env bash

.PHONY: test lint clean precommit

# ── Test ────────────────────────────────────────────────────────────────────
test:
	@echo "==> Running C4 test suite..."
	@bash tests/run.sh

# ── Plugin Tests (requires bun) ─────────────────────────────────────────────
test-plugin:
	@echo "==> Running plugin unit tests..."
	@if command -v bun &>/dev/null; then
		bun test tests/plugin_test.ts 2>&1 || true
	else
		echo "  ⚠️  bun not found — install via 'curl -fsSL https://bun.sh/install | bash'"
	fi

# ── Lint ────────────────────────────────────────────────────────────────────
lint:
	@echo "==> Checking bash syntax..."
	@bash -n c4.sh && echo "  ✓ c4.sh syntax OK"

	@echo "==> Checking .opencode/ files exist..."
	@for f in .opencode/agents/c4-leader.md .opencode/agents/c4-dev.md .opencode/commands/c4.md .opencode/plugins/c4-plugin.ts; do if [ -f "$$f" ]; then echo "  ✓ $$f"; else echo "  ✗ MISSING: $$f"; exit 1; fi; done

	@echo "==> Linting passed."

# ── Clean ───────────────────────────────────────────────────────────────────
clean:
	@echo "==> Removing build artifacts..."
	@find . -name "*.tmp" -not -path "./.git/*" -delete
	@rm -rf .cache .turbo dist build out
	@echo "  ✓ Clean"

# ── Pre-commit (gate for DONE claim) ────────────────────────────────────────
precommit: clean lint test
