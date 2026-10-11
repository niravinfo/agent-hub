# agent-hub

Agent skills and project instructions for **OpenCode** and **VS Code GitHub
Copilot** — no plugins, no global config edits, nothing to install besides
this repo.

## What's in here

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Loaded automatically by both harnesses. Tells the agent which skill to use for which task. Not a README — treat it as agent-facing configuration. |
| `skills/` | Source of truth. One directory per skill, each with a `SKILL.md` (name + description frontmatter, instructions in the body). |
| `setup.ps1` / `setup.sh` | Installers. Make the skills discoverable by agents without editing any IDE or harness configuration. |

The repo deliberately ships the skills in `skills/` and never commits
harness-specific discovery folders: the setup scripts create those locally
as copies or links, so each machine decides what it wants and where. Nothing
in your global config is modified.

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

The default install **copies** the skills into `~/.agents/skills`, which makes
them available in every project: OpenCode and VS Code Copilot both
auto-discover that folder natively, and a `~/.agents/skills` entry takes
precedence over skills offered anywhere else on the machine. Restart any
running agent session after setup.

## Options

| Command | Effect |
| --- | --- |
| `./setup.ps1` / `./setup.sh` | Copy skills into `~/.agents/skills` (all projects) |
| `./setup.ps1 -Mode link` / `./setup.sh --mode link` | Junction / symlink instead of copy — edits to `skills/` apply immediately. Windows junctions need **no admin rights** |
| `./setup.ps1 -Scope local` / `./setup.sh --scope local` | Install into the repo's `.agents/skills` (gitignored) instead of globally — useful for testing changes without touching your whole machine |
| `./setup.ps1 -Clean` / `./setup.sh --clean` | Remove only the entries the script created (never follows links, never deletes source content) |

The scripts are idempotent: re-run them any time to refresh copies or to
repair links.

## Updating

Edit anything under `skills/` and either re-run the script (copy mode) or do
nothing (link mode). Add a new skill by creating `skills/<name>/SKILL.md`
with `name` and `description` frontmatter — `name` must match the directory
name — then re-run the script.

## VS Code Copilot notes

- Skills load automatically when their `description` matches the task, or
  type `/<skill-name>` in chat (e.g. `/brainstorming`).
- The Local agent additionally needs `chat.useAgentsMdFile` enabled in VS
  Code settings to read `AGENTS.md`; the Copilot agent harness reads it by
  default.
- Verify: run `Chat: Open Customizations` from the Command Palette and check
  the **Skills** tab lists the repo's skills.

## OpenCode notes

- Verify: start a session in the repo and use the `skill` tool, or mention
  `@brainstorming` in a prompt.
- If you also use the upstream `superpowers@git+...` plugin, entries created
  by this repo's script take precedence — run with `-Clean` to revert to the
  plugin's set.

## Uninstalling

Run the setup script with `-Clean` / `--clean` (same scope and mode you used
to install). That removes the installed entries; the repo itself stays
intact.
