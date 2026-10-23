# agent-hub

A local library of agent skills, subagent roles, and MCP servers for
**OpenCode** and **GitHub Copilot**. Install once at user level and they are
available in every project.

## What's included

- Process skills for brainstorming, planning, TDD, debugging, code review,
  worktrees, and verification.
- Domain skills for React, React performance, and ClickHouse.
- Subagents for architecture, code review, TypeScript, C#, React, and security
  review.

## Requirements

- Windows: PowerShell 5.1 or newer.
- macOS / Linux: bash.
- The MCP installer on macOS / Linux also needs Python 3.
- Playwright is optional and needs Node.js 18 or newer.

## Install

Run from the repo root.

**Windows**

```powershell
./setup.ps1
```

**macOS / Linux**

```bash
bash setup.sh
```

The installer opens a menu. Choose what to do, which harness to configure
(OpenCode, Copilot, or both), how to install the skills (copy or link), and
whether to install them globally or into one project. It prints a summary and
asks before writing anything.

- **Copy** stores a snapshot. Re-run the installer after changing this repo.
- **Link** points at this repo, so skill edits apply immediately.
- **Global** installs for every project on your machine.
- **Local** installs into a project folder you choose.

Restart any running agent session afterwards.

## What gets installed

| Item | Global | Local |
| --- | --- | --- |
| Skills | `~/.agents/skills/` | `<project>/.agents/skills/` |
| Rules | `~/.config/opencode/AGENTS.md` and `~/.copilot/copilot-instructions.md` | `<project>/AGENTS.md` |
| OpenCode agents | `~/.config/opencode/agents/` | `<project>/.opencode/agents/` |
| Copilot agents | `~/.copilot/agents/` | `<project>/.github/agents/` |

The rules files tell agents which skill to load for a task and how to use the
subagents. They are installed by default because skills are discovered either
way, but are not reliably used without them. If a rules or agent file already
exists and differs from the template, the installer leaves it untouched and
prints a warning.

## MCP servers

The MCP installer adds two remote, keyless servers: **Context7** for library
documentation and **DeepWiki** for questions about public GitHub repositories.

**Windows**

```powershell
./setup-mcp.ps1
```

**macOS / Linux**

```bash
bash setup-mcp.sh
```

The wizard asks whether to configure user or project level, which app to
configure (OpenCode and/or Copilot), and which servers to add. Existing
entries are kept, files are backed up as `.bak`, and it asks before writing.
If an OpenCode config contains JSONC comments, the installer leaves it
untouched and prints the block to merge by hand.

For manual configuration, VS Code, and the optional Playwright browser server,
see [mcp/README.md](mcp/README.md).

## Verify

Check MCP servers:

```bash
opencode mcp list
copilot mcp list
```

Check that skills load:

- **OpenCode**: start a session and mention `@brainstorming`.
- **Copilot**: type `/brainstorming` in chat.

## Update or remove

Re-run the skills installer after pulling changes. To remove what it
installed, run it again and choose **Clean up installed files**. Use the same
scope, harness, and target you installed with.

For MCP servers, remove the `context7` and `deepwiki` entries from your config,
or restore its `.bak` copy.

## Add a skill or agent

- **Skill**: create `skills/<name>/SKILL.md` with `name` and `description`
  front matter. The `name` must match the folder name.
- **Agent**: create `agents/<name>.md` with a `description` and a Markdown
  body.

Then re-run the installer. In link mode, later edits to an installed skill
apply immediately.

## Repo layout

| Path | Contents |
| --- | --- |
| `skills/` | Skill sources, one folder per skill |
| `agents/` | Subagent sources |
| `mcp/` | MCP setup guide and config templates |
| `setup/AGENTS.md` | Rules template copied into each harness |
| `lib/` | Installer menu and prompt helpers |
| `tests/` | Installer and prompt tests |

## Credits

The process skills are adapted from
[obra/superpowers](https://github.com/obra/superpowers). The domain skills and reviewer/architect agents are adapted
from [affaan-m/ECC](https://github.com/affaan-m/ECC). Both projects are
MIT-licensed.
