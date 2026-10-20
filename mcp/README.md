# MCP servers

Setup notes for the Model Context Protocol servers this repo supports.

| Guide | For |
| --- | --- |
| [README-opencode.md](README-opencode.md) | OpenCode — user and project level |
| [README-copilot.md](README-copilot.md) | GitHub Copilot — user and workspace level |

VS Code is configured through GitHub Copilot, so it has no separate guide here.

## What the installer covers

`context7` (up-to-date library docs) and `deepwiki` (public GitHub repo Q&A) are
keyless **remote** servers. The installer at the repo root adds both:

```bash
./setup-mcp.sh          # Linux / macOS
./setup-mcp.ps1         # Windows
```

A bare run opens the wizard; `--defaults` installs both at user level
unattended. See the main [README](../README.md#mcp-servers) for the flags.

## Playwright

Playwright is a **local** server: it drives a real browser on your machine
through `npx`. That makes it a different kind of dependency, so it is not part
of the installer — add it by hand with the guide for your client.

Before you add it:

1. Node.js 18 or newer on `PATH`.
2. Install the browser once: `npx playwright install chromium`. The server also
   reports this command if it starts without a browser.

The first run downloads `@playwright/mcp@latest`; later runs reuse the cache.

## If the installer skipped your file

The installer writes plain JSON. If your config contains comments or trailing
commas (JSONC), it leaves the file untouched and tells you so — merge the block
by hand instead. This is the other reason Playwright is documented rather than
installed: existing configs are often JSONC.

## Templates

`opencode.jsonc` and `copilot-user-mcp-config.json` hold the blocks the
installer copies for the two remote servers. The guides above show the same
blocks plus Playwright, for manual setup.
