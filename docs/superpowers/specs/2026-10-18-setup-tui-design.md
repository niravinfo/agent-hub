# Setup TUI — design

Date: 2026-10-18
Status: draft, awaiting human review
Author: agent (brainstorming skill)

## Intent and why

The four installer scripts are correct but their interactive layer is a
numbered prompt: read a line, print a list, repeat. A throwaway spike proved
an arrow-key TUI in pure bash and pure PowerShell is achievable with no new
dependencies, and the human approved that direction. This change replaces the
prompting layer of all four installers with that TUI. Nothing about *what* the
scripts install changes.

## Goals

- Replace the interactive prompts in all four installers with a shared TUI:
  arrow-key single-select, checkbox multi-select, an editable text field, a
  summary block, and a confirm.
- Keep the four scripts behaviourally identical to each other and to today,
  except for the prompt experience.
- Zero new dependencies. Pure bash and pure PowerShell.
- Work on the platforms the scripts already claim: Linux/macOS bash, and
  Windows PowerShell 5.1 and 7.

## Non-goals

- No new install targets, no new options beyond removing the dead ones.
- No TUI framework or external tool (`gum`, `fzf`, `dialog`, PSReadLine).
- No change to install/clean/merge logic, file formats, markers, or backups.
- No synthetic progress widget. The installers' existing per-item output
  (`copied name`, `skipped …`, `removed …`) prints exactly as it does today;
  the TUI neither replaces nor wraps it.
- No mouse support, no theming, no configuration.

## Anti-goals (failure even if it works)

- Any prompt or ANSI output when stdin/stdout is not a terminal. CI must stay
  silent.
- Breaking macOS's stock bash 3.2.
- Breaking PowerShell 5.1, or a legacy Windows console.
- Changing what ends up on disk (byte-for-byte) for the same inputs.
- Comment bloat: narration of obvious code, or rationale the code already
  states.

## Constraints

- **bash 3.2+** (macOS stock). No `${var,,}`, associative arrays, `mapfile`,
  or `read -t` fractional timeouts. The prompt helpers must resolve this
  without a hang: an `Esc` keypress can never block waiting for a sequence
  tail. The exact byte-read technique is a plan-level decision, but it must not
  rely on a fractional `read -t`.
- **PowerShell 5.1+** and PowerShell 7. No PS7-only syntax (ternary, `??`,
  `::new()`, `$IsWindows`).
- **No literal non-ASCII bytes in `.ps1` files.** Build glyphs from `[char]`
  code points at runtime. This removes the UTF-8-without-BOM decoding trap on
  5.1 entirely. `.sh` files may carry UTF-8 literals.
- **ASCII fallback is automatic**, not a flag: if the locale is not UTF-8
  (bash) or the console cannot render the glyphs (PowerShell), swap to an ASCII
  set. `TERM=dumb` implies ASCII in bash.
- **Drawing goes to the terminal, values go to the caller.** In bash the
  helpers must draw to stderr and print the chosen value to stdout, preserving
  the existing `choice="$(menu ...)"` contract, because a live TUI cannot have
  its stdout captured. In PowerShell, draw with `Write-Host` and `return` the
  value.
- **Comments match the existing density.** Explain non-obvious intent only
  (the marker-ownership rules, the escape/read technique, `[char]` glyphs);
  never restate a line of code.

## The wizard

### setup.sh / setup.ps1

1. Action — single-select: Install skills / Clean up installed files. (default
   Install)
2. Harness — checkboxes: `[x] OpenCode`, `[x] Copilot`. Both on by default.
   No "Both" entry. At least one must be selected to advance.
3. Mode — single-select, install only: Copy / Link. (default Copy)
4. Scope — single-select: Global / Local. (default Global)
5. Target folder — editable text field, local scope only. Default is the repo
   root.
6. Summary + confirm. New step for these two scripts (see "Decisions the human
   must confirm"). Lists action, harness, mode, scope, and the resulting
   skills/rules/agents targets.
7. The script's existing output runs unchanged.

### setup-mcp.sh / setup-mcp.ps1

1. Scope — single-select: User level / Project level. (default User)
2. Application — checkboxes: `[x] OpenCode`, `[x] Copilot`. Both on by default.
   At least one required.
3. Servers — checkboxes: `[x] context7`, `[x] deepwiki`. Both on by default.
   At least one required. (Replaces the comma-separated number entry. Empty is
   still rejected: an empty server list means "install all" downstream, the
   opposite of selecting none.)
4. "Ready to install" block + confirm (y/n). Already exists; restyled.
5. The script's existing output runs unchanged.

### Keys, gates, and semantics (uniform across all four)

- `↑`/`↓` move; `Enter` selects or accepts; `Space` toggles a checkbox;
  `1-9` jumps to an option.
- Text field: typing appends, `Backspace` deletes, `Ctrl-U` clears the field,
  `Enter` accepts with inline validation (invalid directory → hint, stay on
  the prompt, exactly as today's loop). Relative and `~` paths normalize as
  today. No `Esc` binding — it exists only to disambiguate arrow sequences.
- Confirm: `Enter` = yes, `n` = no. "No" prints "nothing was changed" and
  exits 0 (mirrors `setup-mcp` today). It is shown whenever the wizard is
  active.
- `Ctrl-C`: the helpers restore the terminal (cursor, raw mode) and the process
  exits 130. A clean abort via "No" is exit 0, not 130.
- **Gate per script, unchanged.** `setup.sh` keeps `-t 0 && -t 1`;
  `setup-mcp.sh` keeps `-t 0 || MCP_ASSUME_TTY=1`. The shared lib exposes
  primitives and does not impose its own terminal check.
- `MCP_ASSUME_TTY=1` keeps its meaning ("pretend a terminal exists"), so its
  tests must drive real keystrokes through a pty; piped line input cannot
  drive a raw-key TUI. Non-tty runs still take the silent default path.

### Flags map onto steps (unchanged contract)

A flag suppresses its own step; the rest still prompt when a terminal is
attached.

- `--skip-opencode` / `--skip-copilot` both feed the application step: that
  step is suppressed and the checkboxes reflect the skips.
- `--scope` / `-Scope` suppresses the scope step; the local target field still
  appears for local scope (no flag controls the path, today or after).
- `--defaults` / `--clean` / `-Clean` / `--yes` / `-Yes` keep their current
  effect on which steps appear.

## Decisions made by the human

1. Scope includes all four installers.
2. Harness/application pickers are checkboxes, both selected by default, no
   "Both" entry.
3. ASCII fallback is automatic, no flag.
4. The dead `--opencode-rules` / `--copilot-rules` / `-OpenCodeRules` /
   `-CopilotRules` options are removed.

## Decisions made by the agent (recorded; the one marked ✱ needs the human)

- **Shared helper files.** Add `lib/tui.sh` (sourced by both `.sh` installers)
  and `lib/tui.ps1` (dot-sourced by both `.ps1` installers). Four consumers
  make four inline copies the wrong call. The scripts are already repo-bound
  (`skills/`, `agents/`, `mcp/`, `setup/AGENTS.md` are relative to the script),
  so a `lib/` sibling changes nothing about how they run.
- **Removing the four dead options is a hard removal.** They were ignored, but
  PowerShell rejects unknown parameters, so any caller passing
  `-OpenCodeRules` will now error. Not listed in the README's options table, so
  the blast radius is small.
- **Glyphs from code points in `.ps1`, literals in `.sh`.** See constraints.
- **No synthetic progress spinner.** Recording that the demo's spinner is
  dropped; it showed nothing real. Existing output carries the feedback.
- **A `tests/` harness is added.** The repo has no tests today, and the only
  way to prove "same results as before" for a prompt-layer rewrite is a
  regression harness: run each installer with `--yes`/`-Yes` against a
  throwaway `HOME`, and diff the resulting tree. Plus pty-driven tests for the
  TUI keys. Zero-dependency (`tests/run.sh`, `tests/run.ps1`).
- **README updated.** The "Interactive setup" transcript (the numbered menu)
  and the MCP section's step description are rewritten to the new look.
- ✱ **`setup.sh` / `setup.ps1` gain a summary + confirm step.** Today they have
  no confirm; the MCP scripts do. Adding one matches the demo the human
  approved and makes the four consistent, but it is the only genuine
  behavioural addition in this change (an interactive run gains one `Enter`).

## What is left to the builder

- How the byte reader avoids a blocking `Esc` on bash 3.2 (see constraints).
- The exact VT-enable and glyph-capability detection heuristics on Windows.
- The test harness's structure and the pty-driving technique per platform.
- The summary block's exact field labels and layout.
- Colours: the design fixes *using* ANSI colours, not a palette.

## Open questions for the human

- The ✱ item above: keep or drop the new summary + confirm for
  `setup.sh` / `setup.ps1`.
