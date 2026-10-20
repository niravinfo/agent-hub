# GitHub Copilot

Copilot reads MCP servers from an `mcpServers` object.

| Level | File | Scope |
| --- | --- | --- |
| User | `~/.copilot/mcp-config.json` | Every workspace |
| Project | `.mcp.json` in the project root | That workspace; commit it to share with the team |

Windows user-level path: `%USERPROFILE%\.copilot\mcp-config.json`.

`.mcp.json` is the workspace file Copilot CLI reads — `.vscode/mcp.json` has not
been read since Copilot CLI 1.0.22. VS Code itself is configured through
Copilot, which is why this repo has no VS Code guide.

The repo's installer can add `context7` and `deepwiki` to the user file. For a
project `.mcp.json`, paste the block below. Playwright is local, so add it by
hand either way.

## Add the servers

Open the file — or create it — and merge the `mcpServers` block:

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
    },
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

Keep any other keys you already have.

## Playwright

- Needs Node.js 18 or newer.
- Install the browser once: `npx playwright install chromium`.
- `command` is a **string**, with the arguments in `args`.
- The first run downloads `@playwright/mcp@latest`.

## Notes

- **Remote servers** use `type: "http"` and a `url`. Headers, if a service needs
  them, go under `headers`.
- **Local servers** use `type: "stdio"` (`"local"` is an accepted alias).
- `tools` limits which tools a server exposes; omit it to expose all of them.
- `env` sets environment variables for a local server.

## Verify

```bash
copilot mcp list
```

Or, from inside a Copilot CLI session, run `/mcp list` (bare `/mcp` opens the
dashboard). Restart the session after changing the file.

## If the installer skipped your file

The installer only rewrites plain JSON. A config with comments or trailing
commas is left untouched, with a message saying so. In that case paste the
`mcpServers` block above by hand.
