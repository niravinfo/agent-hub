---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or git worktree fallback
---

# Using Git Worktrees

## Overview

Ensure work happens in an isolated workspace. Prefer your platform's native worktree tools. Fall back to manual git worktrees only when no native tool is available.

**Core principle:** Detect existing isolation first. The user decides whether a new worktree is created at all. Then use native tools. Then fall back to git. Never fight the harness.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Step 0: Detect Existing Isolation

**Before creating anything, check if you are already in an isolated workspace.**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard:** `GIT_DIR != GIT_COMMON` is also true inside git submodules. Before concluding "already in a worktree," verify you are not in a submodule:

```bash
# If this returns a path, you're in a submodule, not a worktree — treat as normal repo
git rev-parse --show-superproject-working-tree 2>/dev/null
```

**If `GIT_DIR != GIT_COMMON` (and not a submodule):** You are already in a linked worktree. Report it, then ask the user: keep working here, or create a new worktree? Reuse preserves running processes, caches, and uncommitted work — but the choice is the user's. A preference already in your instructions skips the question. Reuse → skip to Step 2 (Project Setup).

Report with branch state:
- On a branch: "Already in isolated workspace at `<path>` on branch `<name>`."
- Detached HEAD: "Already in isolated workspace at `<path>` (detached HEAD, externally managed). Branch creation needed at finish time."

**If `GIT_DIR == GIT_COMMON` (or in a submodule):** You are in a normal repo checkout.

Ask the user — unless a preference is already in your instructions:

> "Create a new worktree, or work in the current directory? A worktree keeps this task off your current branch."

If the user declines, work in place and skip to Step 2.

## Step 1: Create Isolated Workspace

**You have two mechanisms. Try them in this order.**

### 1a. Native Worktree Tools (preferred)

The user has asked for an isolated workspace (Step 0 consent). Do you already have a way to create a worktree? It might be a tool with a name like `EnterWorktree`, `WorktreeCreate`, a `/worktree` command, or a `--worktree` flag. If you do, use it and skip to Step 2.

Native tools handle directory placement, branch creation, and cleanup automatically. Using `git worktree add` when you have a native tool creates phantom state your harness can't see or manage.

Only proceed to Step 1b if you have no native worktree tool available.

### 1b. Git Worktree Fallback

**Only use this if Step 1a does not apply** — you have no native worktree tool available. Create a worktree manually using git.

#### Location Selection

Worktrees live outside the repo, grouped in a sibling `<repo-name>.worktrees/` folder — the main checkout keeps `.git`. Follow this order:

1. **Check your instructions for a declared worktree directory preference.** If the user has already specified one, use it without asking.

2. **Parent folder available?** Use it (also works from inside a linked worktree):
   ```bash
   MAIN_ROOT=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd -P)
   WORKTREES_DIR="$(dirname "$MAIN_ROOT")/$(basename "$MAIN_ROOT").worktrees"
   mkdir -p "$WORKTREES_DIR"
   ```

3. **No usable parent folder** (repo at filesystem root, unwritable parent, sandbox denial): ask the user where to keep this repo's worktrees. Offer a temp directory as a fallback.

#### Branch Setup

Ask the user (skip anything already answered in their instructions):

1. **Which branch should the worktree use?**
   - The current branch — fails if it is checked out in another worktree.
   - A new branch. If new: **from which branch?**
     - Default: the current branch.
     - If the current branch may be stale, offer `origin/<base>` instead (`git fetch`, then `git status -sb`). Forking from an outdated branch bakes old code in.

#### Create the Worktree

```bash
path="$WORKTREES_DIR/$BRANCH_NAME"

git worktree add "$path" "$BRANCH_NAME"              # existing branch
git worktree add "$path" -b "$BRANCH_NAME"           # new branch from current HEAD
git worktree add "$path" -b "$BRANCH_NAME" "$START"  # new branch from $START
cd "$path"
```

**Sandbox fallback:** If `git worktree add` fails with a permission error (sandbox denial), tell the user the sandbox blocked worktree creation and you're working in the current directory instead. Then run setup and baseline tests in place.

## Step 2: Project Setup

Auto-detect and run appropriate setup:

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

## Step 3: Verify Clean Baseline

Run tests to ensure workspace starts clean:

```bash
# Use project-appropriate command
npm test / cargo test / pytest / go test ./...
```

**If tests fail:** Report failures, ask whether to proceed or investigate.

**If tests pass:** Report ready.

### Report

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| Already in linked worktree | Ask: reuse it or create new (Step 0) |
| In a submodule | Treat as normal repo (Step 0 guard) |
| Native worktree tool available | Use it (Step 1a) |
| No native tool | Git worktree fallback (Step 1b) |
| Parent folder available | `<repo>.worktrees/` in it (`mkdir -p`) |
| No parent folder | Ask user where; temp dir as fallback |
| Permission error on create | Sandbox fallback, work in place |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I'm obviously not in a worktree — no need to check" | Run Step 0. Harness-created isolation and submodules both fool eyeballing; the detection commands settle it. |
| "`git worktree add` is quicker than hunting for a native tool" | A native tool (e.g. `EnterWorktree`) owns placement, branching, and cleanup. Bypassing it is the #1 mistake — it creates phantom state your harness can't see or manage. |
| "A worktree can live inside the repo root" | Worktrees go in `<repo>.worktrees/` next to the repo — outside version control, no `.gitignore` games. |
| "Any directory name works" | Explicit instructions first, then `<repo>.worktrees/` in the repo's parent folder. |
| "The workspace is fresh — baseline tests can wait" | A dirty baseline makes every later failure ambiguous. Run the tests now; proceeding past failures is your human partner's call. |
