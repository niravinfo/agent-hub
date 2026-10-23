# OpenCode

OpenCode reads MCP servers from the `mcp` block of its config file.

| Level | File | Scope |
| --- | --- | --- |
| User | `~/.config/opencode/opencode.jsonc` | Every project on the machine |
| Project | `opencode.json` in the project root | That project only; overrides the user file |

Windows user-level path: `%USERPROFILE%\.config\opencode\opencode.jsonc`.

The repo's installer can add `context7` and `deepwiki` for you. Playwright is a
local server, so add it by hand.

## Add the servers

Open the file — or create it — and merge the `mcp` block:

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
      },
      "playwright": {
        "type": "local",
        "command": ["npx", "-y", "@playwright/mcp@latest"]
      }
    }
  }
}
```

Keep any other keys you already have. A server can be switched off without
deleting it by setting `"enabled": false`.

## Playwright

- Needs Node.js 18 or newer.
- Install the browser once: `npx playwright install chromium`.
- `command` is an **array** — program first, then its arguments.
- The first run downloads `@playwright/mcp@latest`.

## Notes

- **Remote servers** use `type: "remote"` and a `url`. If a service asks for a
  token, add it under `headers`, for example
  `"headers": { "Authorization": "Bearer MY_API_KEY" }`.
- **Local servers** use `type: "local"` and the array form of `command`.
- Environment variables for a local server go under `environment`.

## Verify

```bash
opencode mcp list
```

This lists the configured servers and their authentication state. Restart any
running OpenCode session after changing the file.

## If the installer skipped your file

OpenCode accepts JSONC, so a hand-edited `opencode.jsonc` may contain comments.
The installer only rewrites plain JSON: when it finds comments, it leaves the
file alone and says so. In that case paste the `mcp` block above by hand.
