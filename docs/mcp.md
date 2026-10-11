# MCP setup — Context7 + DeepWiki (remote, no local hosting)

This repo helps you set up **your own machine**: it ships copy-paste templates
and an installer for two remote MCP servers. Nothing to host or run locally —
each harness just needs the URL (plus a free API key for Context7 if you want
higher rate limits).

| Server | What it does | URL | Auth |
| --- | --- | --- | --- |
| Context7 | Up-to-date, version-specific library docs and code examples (`resolve-library-id`, `query-docs`). Say `use context7` in a prompt. | `https://mcp.context7.com/mcp` | Optional API key (free at `https://context7.com/dashboard`). Works without one at anonymous rate limits. |
| DeepWiki | Ask questions about any public GitHub repo (architecture, how-to, code search across the repo). | `https://mcp.deepwiki.com/mcp` | None — public endpoint. |

## Automatic setup (recommended)

```bash
./setup-mcp.sh          # Linux / macOS
./setup-mcp.ps1         # Windows
```

What it does:

- **OpenCode:** merges both servers into the `mcp` block of your global
  `~/.config/opencode/opencode.json` (created if missing) → available in
  every project.
- **Copilot:** merges both servers into `~/.copilot/mcp-config.json`
  (portable format, read by Copilot tools and the Agent Host) → available in
  every workspace.

Safety: server definitions come from this repo's `mcp/` templates, your
existing servers are never overwritten, nothing secret is written, every
touched file is backed up as `<file>.bak`, and a target that isn't plain
JSON (e.g. JSONC with comments) is left untouched with manual instructions.
Idempotent — re-run any time. `./setup-mcp.sh --clean` removes only the
entries pointing at these URLs.

## Manual setup

Templates live in `mcp/`. Copy the block you need:

| Template | Destination | Scope |
| --- | --- | --- |
| `mcp/opencode.jsonc` → `mcp` block | `~/.config/opencode/opencode.json` | OpenCode, every project |
| `mcp/opencode.jsonc` → whole file | `<project>/opencode.json` | OpenCode, one project |
| `mcp/vscode-workspace-mcp.json` | `<project>/.vscode/mcp.json` | VS Code + Copilot, one workspace (commit it to share with your team) |
| `mcp/copilot-user-mcp-config.json` | `~/.copilot/mcp-config.json` | Copilot tools + Agent Host, every workspace |

Verify:

- OpenCode: restart the session, then `opencode mcp list` (+
  `opencode mcp debug context7` / `opencode mcp debug deepwiki` on failure).
- VS Code: trust the workspace if asked, then **MCP: List Servers** from the
  Command Palette — both servers should show as running (**Show Output** on
  failure). In chat, **Configure Tools** lists the new tools.

Reference: `https://opencode.ai/docs/mcp-servers/`,
`https://code.visualstudio.com/docs/agent-customization/mcp-servers`

## Adding your Context7 API key (optional)

The defaults above work with no key. A free key (from
`https://context7.com/dashboard`) raises your rate limits. Add it per harness:

**OpenCode** — set the env var, then add a `headers` block to the `context7`
entry (global `~/.config/opencode/opencode.json` or project `opencode.json`):

```bash
export CONTEXT7_API_KEY="your-key-here"
```

```json
"context7": {
  "type": "remote",
  "url": "https://mcp.context7.com/mcp",
  "headers": {
    "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"
  },
  "oauth": false,
  "enabled": true
}
```

(`Authorization: Bearer {env:CONTEXT7_API_KEY}` works too. `oauth: false`
keeps OpenCode from attempting an OAuth flow, since this server uses a static
key.)

**VS Code** — add a `headers` entry plus an `inputs` prompt to the workspace
`.vscode/mcp.json`. VS Code asks for the key once, stores it securely, and
never writes it into the file:

```json
{
  "servers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "Authorization": "Bearer ${input:context7-api-key}"
      }
    }
  },
  "inputs": [
    {
      "type": "promptString",
      "id": "context7-api-key",
      "description": "Context7 API key (free at https://context7.com/dashboard)",
      "password": true
    }
  ]
}
```

Note: servers using `${input:...}` variables are not forwarded to Agent Host
sessions — keep the keyless config for those, or use the user-level config.

## Tell your agent to use them (optional, for your own `AGENTS.md`)

```markdown
## External docs via MCP (if configured)

- Library/API docs: use the `context7` MCP tools (`resolve-library-id`, then `query-docs`).
- Public GitHub repo questions: use the `deepwiki` MCP tools.
- If the MCP servers aren't configured, fall back to web search.
```

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| Context7 returns 401 / rate-limit errors | Missing or wrong API key — only relevant if you added one. Re-check it (VS Code: **MCP: List Servers** → restart server and re-enter; OpenCode: `echo $CONTEXT7_API_KEY`). |
| Server shows as failed to start | No network access to the URL, or a proxy blocking it. Check **Show Output** (VS Code) / `opencode mcp debug <name>` (OpenCode). Both endpoints answer a plain MCP `initialize` POST with HTTP 200 — if that fails from your shell, the harness can't reach them either. |
| Tools don't appear in chat | Restart the session after changing config. VS Code: check **Configure Tools** in chat; OpenCode: `opencode mcp list`. |
| Installer skipped your file (not plain JSON) | Your config has comments (JSONC). Copy the block from the matching `mcp/` template manually. |
| Prompted for the key on every restart (VS Code) | Stored-input glitch — remove and re-add the server via **MCP: List Servers**, or switch to the user-level config. |
