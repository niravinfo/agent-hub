# agent-hub

Agent skills for **OpenCode** and **VS Code GitHub Copilot** — no plugins required, and nothing to install besides this repo. The default install is **user level**: skills land in `~/.agents/skills` and are available in every project on the machine, plus the skill-discipline rules (`setup/AGENTS.md`) copied into your global config (`~/.config/opencode/AGENTS.md`, `~/.copilot/copilot-instructions.md`). Prefer a single project? Local scope installs into any project folder you pick, without touching user level.

## What's in here

| Path | Purpose |
| --- | --- |
| `setup/AGENTS.md` | Template of the skill-discipline config. Copied to a project's root as `AGENTS.md` by local-scope installs, and to each harness's always-on user file by global installs. Not auto-read from here — it takes effect only where installed. |
| `skills/` | Source of truth. One directory per skill, each with a `SKILL.md` (name + description frontmatter, instructions in the body). |
| `agents/` | Source of truth for reviewer/architect subagents (OpenCode `mode: subagent` format). Installed by the setup scripts as OpenCode user agents and Copilot `.agent.md` files. |
| `setup.ps1` / `setup.sh` | Installers. Make the skills discoverable by agents without editing any IDE or harness configuration. They install both `skills/` and `agents/`. |
| `mcp/` | Copy-paste MCP templates (OpenCode block, VS Code workspace file, Copilot user file). |
| `setup-mcp.ps1` / `setup-mcp.sh` | Installers. Interactive: pick where (user/project), which app, which servers. Merge the `mcp/` templates in (never overwrite, always backup); `--defaults` for unattended installs. |

The repo deliberately ships the skills in `skills/` and never commits
harness-specific discovery folders: the setup scripts create those locally
as copies or links, so each machine decides what it wants and where. Global
scope stays user-level and outside any repository; local scope writes into
exactly one project folder you choose (its `.agents/skills` plus an
`AGENTS.md` copy).

## Setup

Pick your OS. Run from the repo root.

**Windows (PowerShell):**

```powershell
./setup.ps1
```

**Linux / macOS (bash):**

```bash
chmod +x setup.sh
./setup.sh
```

The default install **copies** the skills into `~/.agents/skills`, a
user-level folder: OpenCode and VS Code Copilot both auto-discover that folder natively, so the skills become available in every project on the machine without touching a single repository. Restart any running agent session after setup.

If skills of the same name already exist elsewhere on your machine — for example from a plugin such as `superpowers` — both copies are discovered and merge into one list. Nothing here overrides anything else; check your harness's skills list to see what actually loaded.

## Interactive setup

A bare run drives an arrow-key wizard — no docs needed. It asks in order:
what to do (install or clean), which harnesses to configure (`OpenCode`
and/or `Copilot` checkboxes; at least one), how to install skills
(`Copy` or `Link` shortcut), and where (`Global` or `Local` scope) — plus
the project folder for local scope (`Enter` defaults to this repo, so you
never need to copy this repo into your project). It then prints a summary
of everything it resolved to and asks to proceed; answering `n` prints
`nothing was changed` and exits without writing anything.

Move with `↑`/`↓`, toggle a checkbox with `Space`, accept with `Enter`,
and abort with `Ctrl-C`. Any flag you pass upfront skips its question, so
`./setup.sh --mode link` only asks the rest.

```text
Which harness do you want to configure?
❯ [◉] OpenCode
  [◉] Copilot
```

Automation and CI stay safe: with no terminal attached (pipes, CI jobs)
the scripts never prompt and use defaults silently. `-Yes` /
`-NonInteractive` (`--yes` / `--no-prompt`) forces defaults;
`-Interactive` (`--interactive`) forces the wizard and errors when no
terminal is attached.

## Options

| Command | Effect |
| --- | --- |
| `./setup.ps1` / `./setup.sh` | Copy skills into `~/.agents/skills` (all projects) |
| `./setup.ps1 -Mode link` / `./setup.sh --mode link` | Junction / symlink instead of copy — edits to `skills/` apply immediately. Windows junctions need **no admin rights** |
| `./setup.ps1 -Scope local` / `./setup.sh --scope local` | Install into a project folder you pick (default: this repo): `.agents/skills` plus an `AGENTS.md` copy from `setup/AGENTS.md`. Never touches user level — useful for testing changes without touching your whole machine |
| `./setup.ps1 -Clean` / `./setup.sh --clean` | Remove only the entries the script created (never follows links, never deletes source content). Also offered in the wizard |
| `./setup.ps1 -Yes` / `./setup.sh --yes` | Answer everything with defaults, no prompts (automation/CI) |
| `./setup.ps1 -Interactive` / `./setup.sh --interactive` | Force the guided wizard (errors with no terminal) |

The scripts are idempotent: re-run them any time to refresh copies or to
repair links.

## Always-on rules — intent mapping in every project

Skills and intent mapping are two separate problems:

- **Skills** (`skills/` → `~/.agents/skills`) are auto-discovered by both
  OpenCode and VS Code Copilot in every project. Done by the default install.
- **Intent mapping** is the discipline of loading the matching skill *before*
  starting work. Discovery alone does not force that. The default install
  writes both harnesses' always-on files for you — no flags needed:

| File written | Effect |
| --- | --- |
| `~/.config/opencode/AGENTS.md` | Combined into every OpenCode session |
| `~/.copilot/copilot-instructions.md` | Copilot **Agent Host** personal instructions, applied in every repository |

Both are always installed — they are required for skills to load properly.

The two harnesses differ here, and the distinction matters:

- **Copilot Agent Host** reads `~/.copilot/copilot-instructions.md`.
- **VS Code Local agent** does not. It keeps user-level instructions in your
  VS Code profile instead. If you use the Local agent, pick `Copilot` in the
  harness menu anyway (the Agent Host file does no harm) and add the same text
  through `Chat: Open Customizations`
  → **Instructions** → user scope. Anything you already have in your profile should be copied across by hand; the script will not touch it.

```powershell
./setup.ps1                  # guided menu: harness, copy/link, scope
./setup.ps1 -Yes             # same, silent with defaults (CI-safe)
```

```bash
./setup.sh                   # guided menu: harness, copy/link, scope
./setup.sh --yes             # same, silent with defaults (CI-safe)
```

Both always-on files are copies of the `setup/AGENTS.md` template — the same
file a local-scope install writes to a project root. The full skill discipline
travels with them: the skill catalog, the loading instructions, the tool
mapping, the agent table, and the precedence rule. Plain Markdown, no
frontmatter (frontmatter is only for `*.instructions.md`).

One caveat: because the same template goes to both files, the
OpenCode-specific **Tool mapping** section is present in the Copilot file as
well. It is scoped by its heading, but the Copilot model has none of those
tools — ignore that section under Copilot.

Safety rules for these files:

- An existing file that **differs from the template** is never overwritten —
  the script skips it and tells you, so your own content is safe. Back it up
  and remove it first if you want the template version in place.
- Files that still match the template are refreshed when you re-run. If the
  template itself is later edited, an installed copy no longer matches and is
  treated like any other differing file (left alone) — run `-Clean` first, then
  reinstall, to push a template change out.
- Files written by earlier versions of this script (they carry the
  `<!-- agent-hub:managed -->` marker) are recognised as ours and replaced
  with the template on the next run.
- `-Clean` / `--clean` removes only our copies — files that still match the
  template or carry the marker.

Want the full skill discipline inside a specific project too? Run a local-scope install and point it at that project — it copies the `setup/AGENTS.md` template to that project's root (an existing `AGENTS.md` that differs is left alone; local clean removes only identical copies). Both harnesses read a root `AGENTS.md` by default: OpenCode always, the Copilot Agent Host harness by default, and the VS Code Local agent via `chat.useAgentsMdFile` (on by default — only matters if you turned it off).

## Updating

Edit anything under `skills/` and either re-run the script (copy mode) or do
nothing (link mode). Add a new skill by creating `skills/<name>/SKILL.md`
with `name` and `description` frontmatter — `name` must match the directory
name — then re-run the script.

## MCP servers

Remote Context7 (library docs) and DeepWiki (public repo Q&A) — keyless by
default, nothing hosted locally. A bare run of the installer drives the same
arrow-key wizard: where (user level or this project), which applications
(OpenCode and/or Copilot checkboxes; at least one), and which servers
(context7 and/or deepwiki checkboxes; at least one). It then shows exactly
what it will write and asks to proceed before touching anything:

```bash
./setup-mcp.sh          # Linux / macOS
./setup-mcp.ps1         # Windows
```

Pass a flag to skip the questions — `--defaults` installs every server at
user level; `--skip-opencode`, `--skip-copilot`, and `--clean` trim or undo.
Prefer manual setup? Copy a block from `mcp/` into your own global or project
config.

## VS Code Copilot notes

- Skills load automatically when their `description` matches the task, or
  type `/<skill-name>` in chat (e.g. `/brainstorming`).
- The Local agent reads a root `AGENTS.md` by default (`chat.useAgentsMdFile`
  is on unless you disabled it); the Copilot Agent Host harness reads it by default.
- Verify: run `Chat: Open Customizations` from the Command Palette and check
  the **Skills** tab lists your personal skills (`~/.agents/skills`).

## OpenCode notes

- Verify: start a session in the repo and use the `skill` tool, or mention
  `@brainstorming` in a prompt.
- If you also use the upstream `superpowers@git+...` plugin, its skills and yours coexist — both are discovered, and same-named skills both appear.
  To drop this repo's set and go back to the plugin's alone, run with  `-Clean`.

## Uninstalling

Run the setup script with `-Clean` / `--clean` (same scope and mode you used
to install; for local scope, answer the same target path at the prompt).
That removes the installed entries; the repo itself stays
intact.

## Credits

The skills and agents in this repo are copied from two MIT-licensed
upstream projects — all credit goes to their authors:

- **Process skills** — the development workflow in `skills/`
  (`brainstorming`, `writing-plans`, `test-driven-development`,
  `systematic-debugging`, and the others) is copied from
  [obra/superpowers](https://github.com/obra/superpowers) by Jesse Vincent
  and Prime Radiant.
- **Domain skills and agents** — the tech-specific skills in `skills/`
  (e.g. `react-patterns`, `clickhouse-io`) and the reviewer/architect
  subagents in `agents/` are copied and adapted from
  [affaan-m/ECC](https://github.com/affaan-m/ECC).

Both upstream projects are MIT-licensed.
