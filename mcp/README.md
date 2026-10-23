# MCP servers

This repo supports two remote, keyless servers:

| Server | What it does |
| --- | --- |
| `context7` | Up-to-date library and framework documentation |
| `deepwiki` | Questions about public GitHub repositories |

The optional Playwright server is covered below.

## Install with the wizard

**Windows**

```powershell
./setup-mcp.ps1
```

**macOS / Linux**

```bash
bash setup-mcp.sh
```

The wizard asks three things:

1. User level or project level.
2. OpenCode and/or Copilot.
3. `context7` and/or `deepwiki`.

It shows the target files and asks before writing. Existing servers are kept,
and every file it changes is backed up as `<file>.bak`.

## Manual setup

### OpenCode

OpenCode v2 stores servers under `mcp.servers`.

| Level | File |
| --- | --- |
| User | `~/.config/opencode/opencode.json` or `opencode.jsonc` |
| Project | `opencode.json`, `opencode.jsonc`, or `.opencode/opencode.json(c)` |

Add both servers under `mcp.servers`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "context7": {
        "type": "remote",
        "url": "https://mcp.context7.com/mcp"
      },
      "deepwiki": {
        "type": "remote",
        "url": "https://mcp.deepwiki.com/mcp"
      }
    }
  }
}
```

If the file already has an `mcp.servers` object, add the entries there. Do not
put server names directly under `mcp`; OpenCode v2 ignores them.

### GitHub Copilot

| Level | File |
| --- | --- |
| User | `~/.copilot/mcp-config.json` |
| Project | `.mcp.json` in the project root |

Add both servers under `mcpServers`:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    },
    "deepwiki": {
      "type": "http",
      "url": "https://mcp.deepwiki.com/mcp"
    }
  }
}
```

Copilot CLI reads `.mcp.json` for workspace configuration. `.vscode/mcp.json`
is a VS Code file and is not read by the CLI.

### VS Code

VS Code uses `.vscode/mcp.json` with a `servers` object:

```json
{
  "servers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    },
    "deepwiki": {
      "type": "http",
      "url": "https://mcp.deepwiki.com/mcp"
    }
  }
}
```

Use this file in VS Code's Copilot Chat. Copilot CLI uses `.mcp.json` instead.

## Playwright

Playwright runs a real browser on your machine. Install Node.js 18 or newer,
then install the browser once:

```bash
npx playwright install chromium
```

Add the server to the file for your client.

**OpenCode**, under `mcp.servers`:

```jsonc
"playwright": {
  "type": "local",
  "command": ["npx", "-y", "@playwright/mcp@latest"]
}
```

**Copilot**, under `mcpServers`:

```json
"playwright": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@playwright/mcp@latest"]
}
```

**VS Code**, under `servers`:

```json
"playwright": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@playwright/mcp@latest"]
}
```

The first run downloads `@playwright/mcp@latest`; later runs use the cache.

## Verify

```bash
opencode mcp list
copilot mcp list
```

Inside a Copilot CLI session, `/mcp list` also works. Restart any open session
after changing a config file.

## Troubleshooting

- **The installer skipped my file.** It only rewrites plain JSON. A JSONC file
  with comments is left untouched; merge the block by hand.
- **A server name is already taken.** If the name is used for a different URL,
  the installer keeps your entry and leaves it alone.
- **I need the previous file.** Every changed file has a `.bak` copy next to it.
- **I want to remove the servers.** Delete their entries, or restore the
  `.bak` copy.
