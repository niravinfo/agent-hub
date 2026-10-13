# agent-hub

Agent skills and project instructions for **OpenCode** and **VS Code GitHub
Copilot** — no plugins required, and nothing to install besides this repo.
Files in your global config are only written by flags you opt into.

## What's in here

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Loaded automatically by both harnesses. Tells the agent which skill to use for which task. Not a README — treat it as agent-facing configuration. |
| `skills/` | Source of truth. One directory per skill, each with a `SKILL.md` (name + description frontmatter, instructions in the body). |
| `setup.ps1` / `setup.sh` | Installers. Make the skills discoverable by agents without editing any IDE or harness configuration. |
| `docs/mcp.md` | MCP guide: remote Context7 + DeepWiki for OpenCode and VS Code Copilot. See [MCP servers](#mcp-servers). |
| `mcp/` | Copy-paste MCP templates (OpenCode block, VS Code workspace file, Copilot user file). |
| `setup-mcp.ps1` / `setup-mcp.sh` | Installers. Merge the `mcp/` templates into your user-level configs (never overwrite, always backup). |

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
| `./setup.ps1 -OpenCodeRules` / `./setup.sh --opencode-rules` | Also write `~/.config/opencode/AGENTS.md` — OpenCode's always-on global rules |
| `./setup.ps1 -CopilotRules` / `./setup.sh --copilot-rules` | Also write `~/.copilot/copilot-instructions.md` — Copilot's user-level instructions, applied in every repository |
| `./setup.ps1 -Clean` / `./setup.sh --clean` | Remove only the entries the script created (never follows links, never deletes source content) |

The scripts are idempotent: re-run them any time to refresh copies or to
repair links.

## Always-on rules — intent mapping in every project

Skills and intent mapping are two separate problems:

- **Skills** (`skills/` → `~/.agents/skills`) are auto-discovered by both
  OpenCode and VS Code Copilot in every project. Done by the default install.
- **Intent mapping** is the discipline of loading the matching skill *before*
  starting work. Discovery alone does not force that.

Each harness has exactly one always-on user-level file that can supply the
nudge. Install only the one you need:

| Flag | File written | Effect |
| --- | --- | --- |
| `-OpenCodeRules` / `--opencode-rules` | `~/.config/opencode/AGENTS.md` | Combined into every OpenCode session |
| `-CopilotRules` / `--copilot-rules` | `~/.copilot/copilot-instructions.md` | Copilot personal instructions, applied in every repository |

```bash
./setup.sh --copilot-rules      # or ./setup.ps1 -CopilotRules
```

The generated file is deliberately short — one paragraph of discipline and
nothing else. The skill descriptions are already in context through skills
discovery, so repeating them would only bloat every prompt. It is **not** a
copy of `AGENTS.md`, and nothing is written into any repository.

Safety rules for these files:

- They carry a `<!-- agent-hub:managed -->` marker. Existing files **without**
  the marker are never overwritten — the script skips them and tells you, so
  your own content is safe. Back it up and remove it first if you want the
  script's version in place.
- Files **with** the marker are refreshed when you re-run.
- `-Clean` (passed with the same flag) removes only the marked file.

Want the repo's own `AGENTS.md` read inside a specific project? That stays
manual and per-repo — put or link `AGENTS.md` at that repo's root. VS Code's
Local agent needs `chat.useAgentsMdFile` enabled for it; the Copilot harness
reads it by default.

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
