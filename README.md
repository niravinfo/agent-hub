# agent-hub

Agent skills for **OpenCode** and **VS Code GitHub Copilot** — no plugins required, and nothing to install besides this repo. The default install is **user level**: skills land in `~/.agents/skills` and are available in every project on the machine, plus short always-on rules files in your global config (`~/.config/opencode/AGENTS.md`, `~/.copilot/copilot-instructions.md`). Nothing is written into any repository.

## What's in here

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Skill-discipline config for agents working **inside this repo**: which skill to use for which task. Read automatically when the session's working directory is this repo. The setup scripts do **not** install it anywhere — see *Always-on rules* below. |
| `skills/` | Source of truth. One directory per skill, each with a `SKILL.md` (name + description frontmatter, instructions in the body). |
| `setup.ps1` / `setup.sh` | Installers. Make the skills discoverable by agents without editing any IDE or harness configuration. |
| `docs/mcp.md` | MCP guide: remote Context7 + DeepWiki for OpenCode and VS Code Copilot. See [MCP servers](#mcp-servers). |
| `mcp/` | Copy-paste MCP templates (OpenCode block, VS Code workspace file, Copilot user file). |
| `setup-mcp.ps1` / `setup-mcp.sh` | Installers. Merge the `mcp/` templates into your user-level configs (never overwrite, always backup). |

The repo deliberately ships the skills in `skills/` and never commits
harness-specific discovery folders: the setup scripts create those locally
as copies or links, so each machine decides what it wants and where. Everything
stays user-level and outside any repository.

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

A bare run guides you — no docs needed. It asks in order: what to do
(install or clean), which harness (`Both` / `OpenCode` / `Copilot`),
how to install skills (`Copy` or `Link` shortcut), and where
(`Global` or `Local` scope). Press `Enter` for the default, or type a
number or name. Any flag you pass upfront skips its question, so
`./setup.sh --mode link` only asks the rest.

```text
What do you want to do?
  [1] Install skills (default)
  [2] Clean up installed files
Select [1-2, Enter=1]:
Which harness do you want to configure?
  [1] Both (OpenCode + Copilot) (default)
  [2] OpenCode only
  [3] Copilot only
Select [1-3, Enter=1]:
```

Automation and CI stay safe: with no terminal attached (pipes, CI jobs)
the scripts never prompt and use defaults silently. `-Yes` /
`-NonInteractive` (`--yes` / `--no-prompt`) forces defaults;
`-Interactive` (`--interactive`) forces the menu and errors when no
terminal is attached.

## Options

| Command | Effect |
| --- | --- |
| `./setup.ps1` / `./setup.sh` | Copy skills into `~/.agents/skills` (all projects) |
| `./setup.ps1 -Mode link` / `./setup.sh --mode link` | Junction / symlink instead of copy — edits to `skills/` apply immediately. Windows junctions need **no admin rights** |
| `./setup.ps1 -Scope local` / `./setup.sh --scope local` | Install into the repo's `.agents/skills` (gitignored) instead of globally — useful for testing changes without touching your whole machine. Local scope installs skills only; the user-level rules files are skipped |
| `./setup.ps1 -Clean` / `./setup.sh --clean` | Remove only the entries the script created (never follows links, never deletes source content). Also offered in the menu |
| `./setup.ps1 -Yes` / `./setup.sh --yes` | Answer everything with defaults, no prompts (automation/CI) |
| `./setup.ps1 -Interactive` / `./setup.sh --interactive` | Force the guided menu (errors with no terminal) |

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

The generated file is deliberately short — one paragraph of discipline and
nothing else, plain Markdown with no frontmatter (frontmatter is only for
`*.instructions.md`). The skill descriptions are already in context through skills
discovery, so repeating them would only bloat every prompt. It is **not** a
copy of this repo's `AGENTS.md`: it carries the priority rule only, with no skill catalog and no tool mapping. That full file stays local to this repo — nothing in the setup scripts propagates it.

Safety rules for these files:

- They carry a `<!-- agent-hub:managed -->` marker. Existing files **without**
  the marker are never overwritten — the script skips them and tells you, so your own content is safe. Back it up and remove it first if you want the
  script's version in place.
- Files **with** the marker are refreshed when you re-run.
- `-Clean` / `--clean` removes only the marked files.

Want the repo's own `AGENTS.md` read inside a specific project? That stays manual and per-repo — put or link `AGENTS.md` at that repo's root. VS Code's Local agent needs `chat.useAgentsMdFile` enabled for it; the Copilot Agent Host harness reads it by default.

## Updating

Edit anything under `skills/` and either re-run the script (copy mode) or do
nothing (link mode). Add a new skill by creating `skills/<name>/SKILL.md`
with `name` and `description` frontmatter — `name` must match the directory
name — then re-run the script.

## MCP servers

Remote Context7 (library docs) and DeepWiki (public repo Q&A) — keyless by
default, nothing hosted locally. Automatic install into your user-level
configs (OpenCode global + Copilot user file, with backup, never overwrite):

```bash
./setup-mcp.sh          # Linux / macOS
./setup-mcp.ps1         # Windows
```

Prefer manual setup? Copy a block from `mcp/` into your own global or project
config. Full guide (both harnesses, API-key opt-in, troubleshooting):
`docs/mcp.md`.

## VS Code Copilot notes

- Skills load automatically when their `description` matches the task, or
  type `/<skill-name>` in chat (e.g. `/brainstorming`).
- The Local agent additionally needs `chat.useAgentsMdFile` enabled in VS
  Code settings to read `AGENTS.md`; the Copilot Agent Host harness reads it by default.
- Verify: run `Chat: Open Customizations` from the Command Palette and check
  the **Skills** tab lists your personal skills (`~/.agents/skills`).

## OpenCode notes

- Verify: start a session in the repo and use the `skill` tool, or mention
  `@brainstorming` in a prompt.
- If you also use the upstream `superpowers@git+...` plugin, its skills and yours coexist — both are discovered, and same-named skills both appear.
  To drop this repo's set and go back to the plugin's alone, run with  `-Clean`.

## Uninstalling

Run the setup script with `-Clean` / `--clean` (same scope and mode you used
to install). That removes the installed entries; the repo itself stays
intact.
