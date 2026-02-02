---
description: Run pre-flight checks and environment setup before starting a workflow
argument-hint: [--claude] [--fix]
allowed-tools: Bash, Read, Glob, AskUserQuestion
---

# Pre-flight Checks & Setup

Verify that the environment is ready for a subagent workflow. Run this before `/subagents:dispatch` or `/subagents:dispatch-claude`.

## Arguments

- `--claude`: Optional. Claude-only mode — skip Codex MCP check (use before `dispatch-claude`)
- `--fix`: Optional. Attempt to fix issues automatically (install missing tools, plugins)

Parse from $ARGUMENTS to extract flags.

## Checks

Run each check via Bash. Report results as pass/fail with fix instructions.

### 1. Git

```bash
git --version 2>/dev/null || echo "FAIL"
```

If missing:
```
FAIL: git is not installed or not functional.
Fix:  install git (https://git-scm.com/downloads)
```

### 2. Superpowers Plugin

```bash
ls ~/.claude/plugins/*/skills/brainstorming/SKILL.md 2>/dev/null | head -1
```

If missing:
```
FAIL: superpowers plugin not installed (required for brainstorming skill).
Fix:  claude plugin install <path-to-superpowers>
```

### 3. Project Environment

```bash
# Check for build/test tooling
make --version 2>/dev/null || npm --version 2>/dev/null || echo "WARN:no-build-tool"

# Check for lint/test targets
make -n lint 2>/dev/null || npm run lint --if-present 2>/dev/null || echo "WARN:no-lint"
make -n test 2>/dev/null || npm run test --if-present 2>/dev/null || echo "WARN:no-test"
```

Warnings are informational — workflows can still run without lint/test targets.

### 4. Codex MCP

**Skip this check if `--claude` is set.**

```bash
# Check if codex-high MCP is available (for dispatch Codex mode)
echo '{"prompt":"ping","approval-policy":"never"}' | timeout 10 claude mcp call codex-high codex 2>/dev/null || echo "WARN:no-codex"
```

If missing:
```
WARN: Codex MCP not available. Use /subagents:dispatch-claude for Claude-only mode,
      or /subagents:dispatch with automatic Codex fallback.
```

## Output

Display a summary table:

```
Pre-flight Results
==================
 ✓ git            git version 2.x.x
 ✓ superpowers    brainstorming skill found
 ✓ build tools    make / npm available
 ⚠ lint           no lint target found
 ⚠ test           no test target found
 ⚠ codex MCP      not available (use dispatch-claude)

Ready: Yes (2 warnings)
```

With `--claude`:

```
Pre-flight Results (Claude-only)
=================================
 ✓ git            git version 2.x.x
 ✓ superpowers    brainstorming skill found
 ✓ build tools    make / npm available
 ⚠ lint           no lint target found
 - codex MCP      skipped (Claude-only mode)

Ready: Yes (1 warning)
```

If any FAIL checks exist, show `Ready: No` and list required fixes.

If `--fix` flag is set, attempt automatic fixes for failed checks and re-run.
