# AGENTS.md

## Skill discipline — before ANY response or action

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a skill might apply to what you are
doing, you ABSOLUTELY MUST load and follow that skill before responding.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. You cannot rationalize your way out of this.
</EXTREMELY-IMPORTANT>

- Load relevant skills before any response or action — including before
  clarifying questions, file reads, or commands.
- Process skills set the approach; implementation skills execute it.
- "Let's build X" → `brainstorming`, then planning skills.
- "Fix this bug" → `systematic-debugging`, then domain skills.
- Implementing a feature or bugfix → `test-driven-development`.
- Announce the skill you load.

## Skill catalog

| Trigger | Skill |
| --- | --- |
| Creating something new or planning anything (features, refactors, talks, renovations) | `brainstorming` |
| A spec or requirements exist and the work is multi-step | `writing-plans` |
| Writing any production code or test | `test-driven-development` |
| Any bug, test failure, or unexpected behavior | `systematic-debugging` |
| Executing a plan yourself, inline, with no subagent tool | `executing-plans` |
| Executing a plan with independent tasks via subagents | `subagent-driven-development` |
| Two or more independent tasks with no shared state | `dispatching-parallel-agents` |
| Feature work needing isolation from the current workspace | `using-git-worktrees` |
| About to claim work is complete, fixed, or passing | `verification-before-completion` |
| Finishing work and deciding how to integrate it | `finishing-a-development-branch` |
| Reviewing changes, or preparing to merge | `requesting-code-review` |
| Receiving code review feedback | `receiving-code-review` |
| Writing or reviewing React components (hooks, server/client boundaries, Suspense, forms, a11y) | `react-patterns` |
| React/Next.js performance work (re-renders, waterfalls, bundle size, server-side) | `react-performance` |
| Writing ClickHouse schemas or queries, or a slow analytical query | `clickhouse-io` |

## Loading skills

- OpenCode: call the `skill` tool with the skill ID, or mention `@<skill-id>`.
- VS Code Copilot: skills load automatically by description, or type `/<skill-id>` in chat.
- If the skill ID is not discoverable, read the file directly: `.agents/skills/<skill-id>/SKILL.md` in a local-scope project, or `~/.agents/skills/<skill-id>/SKILL.md` for the user-level library.

## Tool mapping (OpenCode)

When a skill references a tool, substitute the OpenCode equivalent:

- Todos → no todo tool exists; track the plan in a markdown file or the harness's plan facility.
- `Subagent (general-purpose):` → `subagent` tool, `agent: "general"` (`description`, `prompt`; `background` optional; pass `sessionID` to continue a previous subagent).
- Skill invocation → the `skill` tool.
- Read files → `read`.
- Create, edit, or delete files → `patch` (`patchText`), else `write` / `edit`; deletions via `shell`.
- Shell commands → `shell` (`command`, `workdir`, `timeout`, `background`).
- Search files → `grep`, `glob`.
- Fetch a URL → `webfetch`; search the web → `websearch`.

## Subagents

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a task the parent already
scoped and authorized, execute that task. Never restart controller workflows
(brainstorming, plan approval) — the parent has already approved the work.
Implementation skills (`test-driven-development`, `systematic-debugging`,
`verification-before-completion`) still apply in full.
</SUBAGENT-STOP>

## Agents

| Trigger | Agent |
| --- | --- |
| Reviewing `.tsx`/`.jsx` changes (hooks, perf, a11y, RSC boundaries) | `react-reviewer` |
| Reviewing TypeScript/JavaScript for type safety and async correctness | `typescript-reviewer` |
| React build failure across Vite, webpack, or Next.js | `react-build-resolver` |
| Reviewing C# / .NET changes (conventions, async, nullable types, perf) | `csharp-reviewer` |
| Architecture decisions, trade-offs, ADRs, or cross-service topology calls | `architect` |
| Reviewing code for OWASP risks, secrets, injection, or auth | `security-reviewer` |

## Precedence

This file and direct human requests override skills; skills override default
behavior. Skip a skill only when the human explicitly says to.
