# agent-hub

Agent skills for **OpenCode** and **GitHub Copilot** — no plugins, and nothing to install besides this repo. The default install is **user level**: skills land in `~/.agents/skills` and work in every project on your machine, and the skill-discipline rules are written to each harness's always-on config file so agents load the matching skill before starting work.

## Setup

Run from the repo root.

**Windows (PowerShell):**

```powershell
./setup.ps1
```

**Linux / macOS (bash):**

```bash
chmod +x setup.sh
./setup.sh
```

That is the whole install. Restart any running agent session afterwards. If skills of the same name already exist on your machine — from a plugin such as `superpowers`, say — both sets are discovered and merge into one list; nothing here overrides anything else.

## What the installer asks

A bare run is a guided wizard, so no flags are needed. It asks what to do (install or clean), which harnesses to configure (OpenCode and/or Copilot), how to install skills (copy or link), and where (global or local scope — for local, `Enter` defaults to this repo, so you never need to copy the repo into your project). It prints a summary and confirms before writing anything.

Any flag you pass upfront skips its question, so `./setup.sh --mode link` only asks the rest. With no terminal attached (pipes, CI jobs) the scripts never prompt and use defaults silently.

## Options

| Command | Effect |
| --- | --- |
| `./setup.ps1` / `./setup.sh` | Copy skills into `~/.agents/skills` (all projects) |
| `./setup.ps1 -Mode link` / `./setup.sh --mode link` | Junction / symlink instead of copy — edits to `skills/` apply immediately. Windows junctions need **no admin rights** |
| `./setup.ps1 -Scope local` / `./setup.sh --scope local` | Install into a project folder you pick (default: this repo): `.agents/skills` plus an `AGENTS.md` copy. Never touches user level |
| `./setup.ps1 -Clean` / `./setup.sh --clean` | Remove only the entries the script created (never follows links, never deletes source content) |
| `./setup.ps1 -Yes` / `./setup.sh --yes` | Answer everything with defaults, no prompts (automation/CI) |
| `./setup.ps1 -Interactive` / `./setup.sh --interactive` | Force the guided wizard (errors with no terminal) |

The scripts are idempotent: re-run them any time to refresh copies or repair links.

## Where things go

| File written | Effect |
| --- | --- |
| `~/.agents/skills/` | Skills, auto-discovered by both harnesses in every project |
| `~/.config/opencode/AGENTS.md` | Skill discipline, combined into every OpenCode session |
| `~/.copilot/copilot-instructions.md` | Skill discipline, Copilot **Agent Host** personal instructions |

Both rules files are installed by default — skills do not load properly without them. A file that already exists and **differs** from the template is never overwritten: the script skips it and tells you, and files that still match are refreshed on re-run. A local-scope install writes that same template to the project folder you pick.

## Repo layout

This table matters only if you want to edit the skills themselves.

| Path | Purpose |
| --- | --- |
| `skills/` | Source of truth — one directory per skill, each with a `SKILL.md` (name + description frontmatter) |
| `agents/` | Source of truth for reviewer/architect subagents, installed as OpenCode user agents and Copilot `.agent.md` files |
| `setup/AGENTS.md` | The skill-discipline template the installer copies |
| `setup.ps1` / `setup.sh` | Skill and agent installer |
| `mcp/` | MCP server templates and setup guides for OpenCode and GitHub Copilot |

To add a skill, create `skills/<name>/SKILL.md` with `name` and `description` frontmatter — `name` must match the directory name — then re-run the installer. In link mode there is nothing to re-run: edits apply immediately.

## MCP servers

```bash
./setup-mcp.sh          # Linux / macOS
./setup-mcp.ps1         # Windows
```

The installer adds the two keyless **remote** servers — Context7 (library docs) and DeepWiki (public repo Q&A) — at user or project level. A bare run drives the same kind of wizard: where, which application, and which servers; it shows exactly what it will write and asks before touching anything. Pass `--defaults` to install both unattended; `--skip-opencode`, `--skip-copilot`, and `--clean` trim or undo.

**Playwright** (local browser automation) is not part of the installer: it runs on your machine through `npx`, needs Node.js 18+, and many existing configs are JSONC with comments, which the installer will not rewrite. Add it by hand from the matching guide:

- [OpenCode](mcp/README-opencode.md) — user level and project level
- [GitHub Copilot](mcp/README-copilot.md) — user level (`~/.copilot/mcp-config.json`) and workspace (`.mcp.json`)

VS Code is configured through GitHub Copilot, so there is no separate guide for it.

## Verifying it worked

- **GitHub Copilot**: skills load automatically when their `description` matches the task, or type `/<skill-name>` in chat (e.g. `/brainstorming`).
- **OpenCode**: start a session and use the `skill` tool, or mention `@brainstorming` in a prompt.

## Uninstalling

Run the installer with `-Clean` / `--clean`, using the same scope and mode you installed with (for local scope, answer the same target path at the prompt). The repo itself stays intact.

## Credits

The process skills (`brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, and the others) are copied from [obra/superpowers](https://github.com/obra/superpowers) by Jesse Vincent and Prime Radiant. The domain skills (`react-patterns`, `clickhouse-io`, …) and the reviewer/architect agents are copied and adapted from [affaan-m/ECC](https://github.com/affaan-m/ECC). Both are MIT-licensed — all credit to their authors.
