# ECC Domain Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor 14 ECC domain skills and 6 converted reviewer/architect agents into agent-hub so `setup.ps1/sh` installs them for others on OpenCode and Copilot.

**Architecture:** Skills stay single-source in `skills/<id>/` (Agent Skills standard, already portable). Agents live single-source canonical in `agents/<id>.md` (OpenCode `mode: subagent` + `permissions` frontmatter); setup scripts convert/install copies to OpenCode user agents and Copilot `.agent.md` user agents. No raw ECC frontmatter (`tools: Read,...` / `model: sonnet`) is committed.

**Tech Stack:** Markdown SKILL.md + OpenCode agents md + PowerShell/Bash setup scripts; ECC MIT source with attribution.

**Spec:** This plan implements the locked scope from chat 2026-10-16 (14 skills, 6 agents, no customs for RabbitMQ/MassTransit, SQL Server/Mongo, AngularJS; keep existing 12 process skills; minimal routing merge in `requesting-code-review`).

## Global Constraints

- NEVER run `git commit` unless the user explicitly asks in that same request; leave changes staged/uncommitted.
- Skill `name` field must equal parent directory name, lowercase kebab-case, max 64 chars (Copilot silently drops mismatches).
- No secrets in vendored files; ECC content is MIT — keep `metadata.origin: ECC` + source link where ECC has it.
- Setup scripts stay idempotent, copy/link + clean, never overwrite unmarked user files.
- Default install remains user-level (global); local scope writes only into the chosen project folder.

## Review Focus

- Skill silently not discovered (name/dir mismatch or missing description) — expect `setup.sh --scope local` + `ls .agents/skills/<id>/SKILL.md` to show all 14.
- Reviewer agent edits code when it should only report — expect reviewer permissions to deny `edit` and allow `read/glob/grep`.
- OpenCode rejects agent frontmatter (legacy `tools`/`model: sonnet` left in) — expect no `tools:` string field and no bare `model: sonnet` in `agents/*.md`.
- Copilot agent missing tools array or wrong extension — expect `.agent.md` copies carry `tools:` YAML array.
- Existing 12 process skills broken by catalog edit — expect `setup/AGENTS.md` table still lists all 12 originals plus new domain rows.

---

### Task 1: Vendor 14 ECC skills verbatim

**Files:**
- Create dirs under `skills/` each with `SKILL.md` (+ `references/` only if the ECC skill body links them): `react-patterns`, `react-testing`, `react-performance`, `vite-patterns`, `frontend-patterns`, `dotnet-patterns`, `csharp-testing`, `backend-patterns`, `api-design`, `hexagonal-architecture`, `redis-patterns`, `clickhouse-io`, `database-migrations`, `security-review`
- Modify: none
- Test: `setup.sh --scope local --mode copy` dry listing (no commit)

**Interfaces:**
- Consumes: ECC raw `https://raw.githubusercontent.com/affaan-m/ECC/main/skills/<id>/SKILL.md`
- Produces: `skills/<id>/SKILL.md` with `name: <id>` + `description` preserved; later tasks rely on these IDs for AGENTS.md routing and agent `Related` links.

**Why 14 not 16:** the earlier 16 added `e2e-testing` + `error-handling`; both deferred to phase 2 to hold the locked 14. No RabbitMQ/MassTransit, SQL Server/Mongo, or AngularJS customs in this plan.

- [ ] **Step 1: Fetch and write the 14 skills**

Fetch each URL below via `webfetch` (format text) and write body verbatim under `skills/<id>/SKILL.md`, preserving frontmatter `name`/`description` and adding `metadata.origin: ECC` if absent. Pull `references/` files only when the body links them with a relative path.

```text
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/react-patterns/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/react-testing/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/react-performance/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/vite-patterns/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/frontend-patterns/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/dotnet-patterns/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/csharp-testing/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/backend-patterns/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/api-design/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/hexagonal-architecture/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/redis-patterns/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/clickhouse-io/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/database-migrations/SKILL.md
https://raw.githubusercontent.com/affaan-m/ECC/main/skills/security-review/SKILL.md
```

Verify each file starts with `name: <dir>` and a non-empty `description:` line.

- [ ] **Step 2: Verify**

Run: `ls skills | wc -l` (expect 26 = 12 old + 14 new) and `grep -L "^description:" skills/*/SKILL.md` (expect no output). On Windows use `pwsh -c "(Get-ChildItem skills -Directory).Count"`.

Expected: 26 skill dirs, every SKILL.md has a description.

- [ ] **Step 3: Show for approval (no commit)**

Show `git status --short`. Do not commit.

---

### Task 2: Create 6 canonical agents in `agents/`

**Files:**
- Create: `agents/react-reviewer.md`, `agents/typescript-reviewer.md`, `agents/react-build-resolver.md`, `agents/csharp-reviewer.md`, `agents/architect.md`, `agents/security-reviewer.md`
- Modify: none
- Test: frontmatter lint via `grep` (no commit)

**Interfaces:**
- Consumes: ECC `agents/<id>.md` bodies (review checklists, diagnostic commands, output format) + Task 1 skill IDs for `Related` links.
- Produces: canonical `agents/<id>.md` files that Task 3 installs; Task 4 links them from `setup/AGENTS.md`.

- [ ] **Step 1: Write canonical agent files**

Source of truth is this repo `agents/<id>.md` in OpenCode Markdown-agent format. Body = ECC review workflow adapted (scope, diagnostic commands, severity output, `Related` skills). Frontmatter per file:

```md
---
description: <one-line trigger, e.g. Reviews React/TSX for hooks, perf, a11y, RSC boundaries>
mode: subagent
---
```

Rules for all 6: no `tools:` string field, no `model:` field (inherit session model, avoids provider lock), no `name:` field (ID comes from filename per OpenCode docs). Reviewers get a `permissions:` block denying edits:

```md
---
description: Reviews React/TSX for hooks, perf, a11y, RSC boundaries
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
---
```

`architect.md` omits the deny block (needs edit for proposals) or keeps `edit: ask`. `security-reviewer.md` keeps deny-edit like reviewers. Each body ends with `Related skills:` listing the Task-1 IDs (e.g. csharp body links `dotnet-patterns`, `csharp-testing`).

- [ ] **Step 2: Verify**

Run: `grep -rn "^tools:" agents/ || echo NO_LEGACY_TOOLS` (expect NO_LEGACY_TOOLS) and `grep -rn "model: sonnet" agents/ || echo NO_SONNET` (expect NO_SONNET).

Expected: no legacy ECC frontmatter remains.

- [ ] **Step 3: Show for approval (no commit)**

Show `git status --short`. Do not commit.

---

### Task 3: Extend `setup.ps1` / `setup.sh` to install agents

**Files:**
- Modify: `setup.ps1`, `setup.sh`
- Create: none (installer writes outside repo: OpenCode `~/.config/opencode/agents/`, Copilot `~/.copilot/agents/*.agent.md`; local scope: `<project>/.opencode/agents/` + `<project>/.github/agents/`)
- Test: `./setup.sh --scope local --mode link` in a temp dir (no commit)

**Interfaces:**
- Consumes: `agents/*.md` from Task 2.
- Produces: installed user-level agent copies; Task 4 documents them in README/AGENTS.md.

- [ ] **Step 1: Implement agent install alongside skills**

Mirror the existing skills loop. Global scope: copy/link each `agents/<id>.md` to OpenCode `~/.config/opencode/agents/<id>.md` AND to Copilot `~/.copilot/agents/<id>.agent.md` with frontmatter converted: keep `description`, add Copilot `tools: ['search', 'read', 'grep']` array for reviewers (`architect` also gets `['edit']`), drop OpenCode-only `permissions`/`mode` keys from the Copilot copy (keep them in the OpenCode copy). Local scope: `<target>/.opencode/agents/<id>.md` (verbatim) + `<target>/.github/agents/<id>.agent.md` (converted). Reuse `remove_managed` semantics; `--clean` removes only managed copies. Interactive menu gains no new question: agents follow the same harness/mode/scope answers as skills.

- [ ] **Step 2: Verify**

Run in a scratch dir: `./setup.sh --scope local --mode copy` (or `.\setup.ps1 -Scope local`) pointed at an empty temp project; then `ls <tmp>/.opencode/agents | wc -l` (expect 6) and `ls <tmp>/.github/agents | wc -l` (expect 6).

Expected: 6 + 6 converted copies, skills install unchanged.

- [ ] **Step 3: Show for approval (no commit)**

Show `git diff --stat`. Do not commit.

---

### Task 4: Wire catalog, routing, and docs; final verification

**Files:**
- Modify: `setup/AGENTS.md` (skill catalog + subagent routing table), `README.md` (What's in here + Options rows for agents)
- Modify (tiny): `skills/requesting-code-review/SKILL.md` — add routing line: `.tsx/.jsx` → `react-reviewer`, `.cs` → `csharp-reviewer`, migration/schema → `database-migrations` skill + `architect` for topology calls. No other process-skill edits.
- Test: full local install + discovery probe (no commit)

**Interfaces:**
- Consumes: Task 1–3 outputs.
- Produces: shippable working tree; reviewer checks it before any merge.

- [ ] **Step 1: Edit catalog and docs**

`setup/AGENTS.md`: append domain skill rows (Trigger → Skill → File) for the 14 and an `Agents` table (Trigger → Agent → Source `agents/<id>.md`). Keep all 12 original process rows untouched. `README.md`: add `agents/` row to What's-in-here and note installers handle skills + agents. `requesting-code-review/SKILL.md`: 3-line routing addition only.

- [ ] **Step 2: Verify end to end**

Run: local-scope install to temp project, then confirm `ls <tmp>/.agents/skills | wc -l` ≥ 14 new, `ls <tmp>/.opencode/agents | wc -l` = 6, `grep -c "react-reviewer" <tmp>/AGENTS.md` ≥ 1, and `grep -L "^description:" agents/*.md` empty.

Expected: all counts pass; `git status --short` shows only intended new/modified files.

- [ ] **Step 3: Request review (no commit)**

Run `requesting-code-review` flow (fresh-context reviewer over the diff) and report findings. Do not commit; leave tree staged/unstaged per user instruction.
