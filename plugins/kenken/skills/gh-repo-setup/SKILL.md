---
name: gh-repo-setup
description: Set up GitHub repo with GitFlow branching, protection rules, templates, and CI
argument-hint: [--existing] [repo-name]
---

# GitHub Repository Setup

> **For Claude:** This skill sets up a GitHub repository with GitFlow branching, branch protection, issue/PR templates, and label-triggered CI.

## When to Use

- Setting up a new GitHub repository with best practices
- Adding GitFlow branching to an existing repo
- Configuring branch protection rules
- Adding issue/PR templates and CI workflows

## Flow

```
1. Check gh auth → login if needed
2. Ask: Create new or configure existing repo?
3. If new: Create repo with gh repo create
4. Setup GitFlow branches (main, develop)
5. Configure branch protection (owner can bypass)
6. Add issue/PR templates
7. Add label-triggered CI workflow
8. Display summary
```

## Phase 1: Authentication

**Check gh auth status:**

```bash
gh auth status
```

If not authenticated, run:

```bash
gh auth login
```

Wait for user to complete authentication before proceeding.

## Phase 2: Repo Selection

**Parse arguments first:**

- If `--existing` flag is present: Skip to "If Configure Existing" section
- If repo name is provided as argument: Use it (don't prompt for name)
- Otherwise: Ask user for mode

**Ask user using AskUserQuestion (only if no --existing flag):**

| Header      | Question                                 | Options                                      |
| ----------- | ---------------------------------------- | -------------------------------------------- |
| "Repo mode" | "Create new repo or configure existing?" | "Create new repo", "Configure existing repo" |

### If Create New Repo:

**Ask for details:**

| Header       | Question                                | Options             |
| ------------ | --------------------------------------- | ------------------- |
| "Visibility" | "Should the repo be public or private?" | "public", "private" |

**Get repo name from arguments or ask:**

If no repo name in arguments, ask user to provide one.

**Create repo (with initial README to enable branch operations):**

```bash
# Use --public or --private based on user selection (lowercase)
# Include --add-readme to create initial commit (required for branch protection)
gh repo create <repo-name> --public --clone --add-readme
# OR
gh repo create <repo-name> --private --clone --add-readme
cd <repo-name>
```

### If Configure Existing:

Verify current directory is a git repo with GitHub remote:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If not a GitHub repo, inform user and exit.

## Phase 3: GitFlow Branch Setup

**Get current branch and repo info:**

```bash
git branch --show-current
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
```

**Ensure main branch exists:**

If default branch is not `main` (e.g., `master`), rename it:

```bash
# Get current default branch name
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)

# If not main, checkout default branch first then rename to main
if [ "$DEFAULT_BRANCH" != "main" ]; then
  git checkout "$DEFAULT_BRANCH"
  git branch -M main
  git push -u origin main
  # Update default branch on GitHub
  gh repo edit --default-branch main
fi
```

**Create develop branch (skip if exists locally or remotely):**

```bash
# Check if develop branch exists locally or on remote
if git show-ref --verify --quiet refs/heads/develop; then
  echo "develop branch already exists locally, skipping creation"
elif git ls-remote --heads origin develop | grep -q develop; then
  echo "develop branch exists on remote, fetching..."
  git fetch origin develop:develop
else
  git checkout -b develop
  git push -u origin develop
fi
git checkout main
```

## Phase 4: Branch Protection

**Get repo owner/name:**

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

**Create ci label for triggering CI:**

```bash
gh label create ci --description "Trigger CI workflow" --color 0E8A16 || true
```

**Protect main branch:**

Note: Status checks are initially set to null because the exact check context
(e.g., "CI / ci") is only known after the first workflow run. After the first
CI run, update protection to require that specific check.

```bash
gh api repos/$REPO/branches/main/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  --input - << 'EOF'
{
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "required_status_checks": null,
  "enforce_admins": false,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

**Protect develop branch:**

```bash
gh api repos/$REPO/branches/develop/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  --input - << 'EOF'
{
  "required_pull_request_reviews": null,
  "required_status_checks": null,
  "enforce_admins": false,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

**Note:** `enforce_admins: false` allows repo owner/admins to bypass protection.
After first CI run, update protection to require the status check using:

```bash
# Get exact check name from a completed PR, then update protection
gh api repos/$REPO/branches/main/protection/required_status_checks \
  -X PATCH --input - << 'EOF'
{
  "strict": true,
  "checks": [{"context": "CI / ci"}]
}
EOF
```

## Phase 5: Templates

**Check for uncommitted changes before proceeding:**

```bash
if [ -n "$(git status --porcelain)" ]; then
  echo "Warning: Uncommitted changes detected"
fi
```

If uncommitted changes exist, use AskUserQuestion:

| Header    | Question                                             | Options             |
| --------- | ---------------------------------------------------- | ------------------- |
| "Changes" | "You have uncommitted changes. Continue with setup?" | "Continue", "Abort" |

If user aborts, exit the skill.

**Create .github directory structure:**

```bash
mkdir -p .github/ISSUE_TEMPLATE .github/workflows
```

**Check for existing template files before creating:**

```bash
# Check if any template files exist
EXISTING_FILES=""
[ -f .github/ISSUE_TEMPLATE/bug_report.md ] && EXISTING_FILES="$EXISTING_FILES bug_report.md"
[ -f .github/ISSUE_TEMPLATE/feature_request.md ] && EXISTING_FILES="$EXISTING_FILES feature_request.md"
[ -f .github/PULL_REQUEST_TEMPLATE.md ] && EXISTING_FILES="$EXISTING_FILES PULL_REQUEST_TEMPLATE.md"
[ -f .github/workflows/ci.yml ] && EXISTING_FILES="$EXISTING_FILES ci.yml"
```

If any files exist, use AskUserQuestion:

| Header     | Question                                 | Options                          |
| ---------- | ---------------------------------------- | -------------------------------- |
| "Existing" | "These files exist: {files}. Overwrite?" | "Overwrite all", "Skip existing" |

**Based on user choice:**

- **Overwrite all**: Create all template files (overwriting existing)
- **Skip existing**: Only create files that don't exist yet

For each file below, check if it should be created based on user choice:

**Create bug report template at `.github/ISSUE_TEMPLATE/bug_report.md` (if not skipping):**

```markdown
---
name: Bug Report
about: Report a bug to help us improve
labels: bug
---

## Description

A clear description of the bug.

## Steps to Reproduce

1.
2.
3.

## Expected Behavior

What should happen.

## Actual Behavior

What actually happens.

## Environment

- OS:
- Version:
```

**Create feature request template at `.github/ISSUE_TEMPLATE/feature_request.md`:**

```markdown
---
name: Feature Request
about: Suggest a new feature
labels: enhancement
---

## Problem

What problem does this solve?

## Proposed Solution

How should it work?

## Alternatives Considered

Other approaches you've thought about.
```

**Create PR template at `.github/PULL_REQUEST_TEMPLATE.md`:**

```markdown
## Summary

Brief description of changes.

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation

## Checklist

- [ ] Tests pass locally
- [ ] Code follows project style
- [ ] Documentation updated (if needed)
```

## Phase 6: CI Workflow

**Create CI workflow at `.github/workflows/ci.yml`:**

```yaml
name: CI

on:
  pull_request:
    types: [labeled, synchronize]
    branches: [main, develop]

jobs:
  ci:
    if: contains(github.event.pull_request.labels.*.name, 'ci')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup (customize for your project)
        run: echo "Add setup steps here"

      - name: Lint
        run: echo "Add lint command here"

      - name: Test
        run: echo "Add test command here"
```

**Note:** CI only runs when PR has the `ci` label.

## Phase 7: Commit and Summary

**Stage and commit all template files (only if changes exist):**

```bash
git add .github/
# Only commit if there are staged changes
git diff --staged --quiet || git commit -m "chore: add GitHub templates and CI workflow

- Bug report and feature request issue templates
- Pull request template
- Label-triggered CI workflow

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Push changes (only if there were commits):**

```bash
# Push to origin, setting upstream if needed
git push -u origin HEAD
```

**Display summary:**

```
GitHub Repository Setup Complete

Repository: {repo-name}

Branches:
  ✓ main (protected: 1 review required)
  ✓ develop (protected)
  Note: Admins can bypass protection rules

Templates Added:
  ✓ .github/ISSUE_TEMPLATE/bug_report.md
  ✓ .github/ISSUE_TEMPLATE/feature_request.md
  ✓ .github/PULL_REQUEST_TEMPLATE.md

CI Workflow:
  ✓ .github/workflows/ci.yml (triggers on 'ci' label)

Next Steps:
  1. Customize .github/workflows/ci.yml for your project
  2. Create first feature branch: git checkout -b feature/my-feature develop
  3. Add 'ci' label to a PR to trigger first CI run
  4. After first CI run, update branch protection to require status checks
```

## Error Handling

| Error                   | Action                                           |
| ----------------------- | ------------------------------------------------ |
| Not authenticated       | Run `gh auth login` and wait                     |
| Repo already exists     | Ask user: configure existing repo or abort       |
| Repo creation fails     | Display error, suggest checking name/permissions |
| Branch protection fails | Check if user has admin access to repo           |
| Not a git repo          | Inform user, exit skill                          |
| develop branch exists   | Skip creation, continue                          |
| Template files exist    | Ask user: overwrite or skip                      |
