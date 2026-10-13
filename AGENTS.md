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

| Trigger | Skill | File |
| --- | --- | --- |
| Creating something new or planning anything (features, refactors, talks, renovations) | `brainstorming` | `skills/brainstorming/SKILL.md` |
| A spec or requirements exist and the work is multi-step | `writing-plans` | `skills/writing-plans/SKILL.md` |
| Writing any production code or test | `test-driven-development` | `skills/test-driven-development/SKILL.md` |
| Any bug, test failure, or unexpected behavior | `systematic-debugging` | `skills/systematic-debugging/SKILL.md` |
| Executing a plan yourself, inline, with no subagent tool | `executing-plans` | `skills/executing-plans/SKILL.md` |
| Executing a plan with independent tasks via subagents | `subagent-driven-development` | `skills/subagent-driven-development/SKILL.md` |
| Two or more independent tasks with no shared state | `dispatching-parallel-agents` | `skills/dispatching-parallel-agents/SKILL.md` |
| Feature work needing isolation from the current workspace | `using-git-worktrees` | `skills/using-git-worktrees/SKILL.md` |
| About to claim work is complete, fixed, or passing | `verification-before-completion` | `skills/verification-before-completion/SKILL.md` |
| Finishing work and deciding how to integrate it | `finishing-a-development-branch` | `skills/finishing-a-development-branch/SKILL.md` |
| Reviewing changes, or preparing to merge | `requesting-code-review` | `skills/requesting-code-review/SKILL.md` |
| Receiving code review feedback | `receiving-code-review` | `skills/receiving-code-review/SKILL.md` |

## Loading skills

- OpenCode: call the `skill` tool with the skill ID, or mention `@<skill-id>`.
- VS Code Copilot: skills load automatically by description, or type `/<skill-id>` in chat.
- If the skill ID is not discoverable, read `skills/<skill-id>/SKILL.md` directly.

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

## Precedence

This file and direct human requests override skills; skills override default
behavior. Skip a skill only when the human explicitly says to.
