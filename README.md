# agent-hub

Agent skills for **OpenCode** and **VS Code GitHub Copilot** — no plugins required, and nothing to install besides this repo. The default install is **user level**: skills land in `~/.agents/skills` and are available in every project on the machine. Nothing is written into any repository, and files in your global config are only written by flags you opt into.

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
as copies or links, so each machine decides what it wants and where. By default they write to user-level locations only; your global config is touched solely by the flags you opt into.

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

## Options

| Command | Effect |
| --- | --- |
| `./setup.ps1` / `./setup.sh` | Copy skills into `~/.agents/skills` (all projects) |
| `./setup.ps1 -Mode link` / `./setup.sh --mode link` | Junction / symlink instead of copy — edits to `skills/` apply immediately. Windows junctions need **no admin rights** |
| `./setup.ps1 -Scope local` / `./setup.sh --scope local` | Install into the repo's `.agents/skills` (gitignored) instead of globally — useful for testing changes without touching your whole machine |
| `./setup.ps1 -OpenCodeRules` / `./setup.sh --opencode-rules` | Also write `~/.config/opencode/AGENTS.md` — OpenCode's always-on global rules |
| `./setup.ps1 -CopilotRules` / `./setup.sh --copilot-rules` | Also write `~/.copilot/copilot-instructions.md` — Copilot **Agent Host** user instructions. The VS Code Local agent does not read this path — see *Always-on rules* below. |
| `./setup.ps1 -Clean` / `./setup.sh --clean` | Remove only the entries the script created (never follows links, never deletes source content) |

The scripts are idempotent: re-run them any time to refresh copies or to
repair links.

## Always-on rules — intent mapping in every project

Skills and intent mapping are two separate problems:

- **Skills** (`skills/` → `~/.agents/skills`) are auto-discovered by both
  OpenCode and VS Code Copilot in every project. Done by the default install.
- **Intent mapping** is the discipline of loading the matching skill *before*
  starting work. Discovery alone does not force that.

Each harness has at most one always-on user-level file that can supply the nudge — and Copilot has one only in Agent Host. Install the one you need:

| Flag | File written | Effect |
| --- | --- | --- |
| `-OpenCodeRules` / `--opencode-rules` | `~/.config/opencode/AGENTS.md` | Combined into every OpenCode session |
| `-CopilotRules` / `--copilot-rules` | `~/.copilot/copilot-instructions.md` | Copilot **Agent Host** personal instructions, applied in every repository |

The two harnesses differ here, and the distinction matters:

- **Copilot Agent Host** reads `~/.copilot/copilot-instructions.md`.
- **VS Code Local agent** does not. It keeps user-level instructions in your
  VS Code profile instead. If you use the Local agent, skip   `-CopilotRules` and add the same text through `Chat: Open Customizations`
  → **Instructions** → user scope. Anything you already have in your profile should be copied across by hand; the script will not touch it.

```bash
./setup.sh --copilot-rules      # or ./setup.ps1 -CopilotRules
```

The generated file is deliberately short — one paragraph of discipline and
nothing else. The skill descriptions are already in context through skills
discovery, so repeating them would only bloat every prompt. It is **not** a
copy of this repo's `AGENTS.md`: it carries the priority rule only, with no skill catalog and no tool mapping. That full file stays local to this repo — nothing in the setup scripts propagates it.

Safety rules for these files:

- They carry a `<!-- agent-hub:managed -->` marker. Existing files **without**
  the marker are never overwritten — the script skips them and tells you, so your own content is safe. Back it up and remove it first if you want the
  script's version in place.
- Files **with** the marker are refreshed when you re-run.
- `-Clean` (passed with the same flag) removes only the marked file.

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
