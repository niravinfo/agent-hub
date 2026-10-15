#!/usr/bin/env bash
#
# Installs this repo's skills into an agent-skills discovery location.
#
# OpenCode and VS Code Copilot both auto-discover ~/.agents/skills and
# .agents/skills, so either scope works with zero configuration.
#
#   Default scope: global (~/.agents/skills) - available in every project.
#   --scope local: .agents/skills inside this repo (gitignored).
#
#   Default mode: copy. Re-run to refresh after editing ./skills.
#   --mode link:  symlink per skill so edits apply immediately.
#
#   --clean removes only entries it can prove are its own (symlinks, or
#   directories containing a matching SKILL.md). It never follows links.
#
#   Interactive by default: with no selection flags, a bare ./setup.sh asks
#   what to do (install or clean), which harness to configure (both /
#   OpenCode / Copilot / neither), how to install skills (copy or link
#   shortcut), and where (global or local scope). Pass any flag explicitly
#   to skip its question; --yes answers everything with defaults
#   (automation/CI). Prompts appear only on a real terminal; pipes and CI
#   fall back to defaults silently.
#
#   Skills discovery is not intent mapping: OpenCode and VS Code Copilot both
#   find ~/.agents/skills on their own, but neither forces the discipline of
#   loading a matching skill before work starts. Both always-on files below
#   are always installed (they are required for skills to load properly):
#       OpenCode  ~/.config/opencode/AGENTS.md          every session
#       Copilot   ~/.copilot/copilot-instructions.md    every repository (Agent Host;
#                                                       Local agent uses profile storage)
#   Existing files are never overwritten unless they carry the managed marker;
#   --clean removes only marked ones. Plain Markdown, no frontmatter required
#   for these always-on files.
#
# Idempotent. No dependencies beyond bash/coreutils. No sudo required.
#
# Usage:
#   ./setup.sh
#   ./setup.sh --mode link
#   ./setup.sh --scope local --mode link
#   ./setup.sh --clean
#   ./setup.sh --yes            # answer everything with defaults (CI-safe)

set -euo pipefail

scope="global"
mode="copy"
clean=0
opencode_rules=0
copilot_rules=0
yes_all=0
interactive=0
scope_explicit=0
mode_explicit=0
rules_explicit=0
skip_opencode_rules=0
skip_copilot_rules=0

usage() {
    sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -ge 2 ]] || { echo "error: --scope needs a value" >&2; exit 2; }
            scope="$2"; scope_explicit=1; shift 2 ;;
        --mode)
            [[ $# -ge 2 ]] || { echo "error: --mode needs a value" >&2; exit 2; }
            mode="$2"; mode_explicit=1; shift 2 ;;
        --clean) clean=1; shift ;;
        --opencode-rules) opencode_rules=1; rules_explicit=1; shift ;;
        --copilot-rules) copilot_rules=1; rules_explicit=1; shift ;;
        --yes|--no-prompt|--non-interactive) yes_all=1; shift ;;
        --interactive) interactive=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

case "$scope" in global|local) ;; *) echo "error: --scope must be global or local" >&2; exit 2 ;; esac
case "$mode" in copy|link) ;; *) echo "error: --mode must be copy or link" >&2; exit 2 ;; esac

can_prompt() { [[ -t 0 && -t 1 ]]; }

# menu TITLE DEFAULT_INDEX OPTION... -> prints chosen index (0-based) to stdout.
# Empty answer (or EOF) selects the default. Accepts number or option name.
menu() {
    local title="$1" default="$2"; shift 2
    local opts=("$@")
    echo "" >&2
    echo "$title" >&2
    local i
    for i in "${!opts[@]}"; do
        local mark=""
        [[ $i == "$default" ]] && mark=" (default)"
        echo "  [$((i+1))] ${opts[$i]}$mark" >&2
    done
    local answer
    while true; do
        printf "Select [1-%s, Enter=%s]: " "${#opts[@]}" "$((default+1))" >&2
        if ! IFS= read -r answer; then echo "" >&2; echo "$default"; return 0; fi
        answer="$(printf '%s' "$answer" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$answer" ]]; then echo "$default"; return 0; fi
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#opts[@]} )); then
            echo "$((answer-1))"; return 0
        fi
        local low
        low="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
        for i in "${!opts[@]}"; do
            local opt_low short
            opt_low="$(printf '%s' "${opts[$i]}" | tr '[:upper:]' '[:lower:]')"
            short="${opt_low%% *}"
            if [[ "$low" == "$opt_low" || "$low" == "$short" ]]; then
                echo "$i"; return 0
            fi
        done
        echo "  Enter 1-${#opts[@]}, a listed name, or empty for default." >&2
    done
}

if [[ $interactive == "1" && $yes_all == "1" ]]; then
    echo "error: cannot combine --interactive with --yes/--no-prompt" >&2; exit 2
fi
if [[ $interactive == "1" ]] && ! can_prompt; then
    echo "error: --interactive requested but no terminal is attached. Run in a terminal or pass flags explicitly." >&2; exit 2
fi

quiet=0
if [[ $yes_all == "1" ]]; then quiet=1; fi
if [[ $interactive == "0" ]] && ! can_prompt; then quiet=1; fi

if [[ $quiet == "0" ]]; then
    if [[ $clean == "0" ]]; then
        # No --clean flag: ask install vs clean. (A passed --clean skips this.)
        choice="$(menu "What do you want to do?" 0 "Install skills" "Clean up installed files")"
        if [[ "$choice" == "1" ]]; then clean=1; fi
    fi
    if [[ $rules_explicit == "0" ]]; then
        if [[ $clean == "1" ]]; then
            choice="$(menu "Which rules files apply?" 0 "Both" "OpenCode only" "Copilot only")"
        else
            choice="$(menu "Which harness do you want to configure?" 0 "Both (OpenCode + Copilot)" "OpenCode only" "Copilot only")"
        fi
        case "$choice" in
            1) skip_copilot_rules=1 ;;
            2) skip_opencode_rules=1 ;;
        esac
    fi
    if [[ $clean == "0" && $mode_explicit == "0" ]]; then
        choice="$(menu "How should skill files be installed?" 0 "Copy (safe snapshot; re-run to refresh)" "Link shortcut (symlink; edits apply immediately)")"
        if [[ "$choice" == "1" ]]; then mode="link"; fi
    fi
    if [[ $scope_explicit == "0" ]]; then
        choice="$(menu "Where should skills be installed?" 0 "Global (~/.agents/skills, every project)" "Local (.agents/skills in this repo only)")"
        if [[ "$choice" == "1" ]]; then scope="local"; fi
    fi
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_dir="$repo_root/skills"
if [[ "$scope" == "global" ]]; then
    target_dir="$HOME/.agents/skills"
else
    target_dir="$repo_root/.agents/skills"
fi

[[ -d "$skills_dir" ]] || { echo "error: skills directory not found: $skills_dir" >&2; exit 1; }

marker='<!-- agent-hub:managed -->'

remove_managed() {
    local path="$1"
    [[ -e "$path" || -L "$path" ]] || return 0
    if [[ -L "$path" ]]; then
        rm "$path"
        echo "  unlinked $path"
    elif [[ -f "$path" ]]; then
        if grep -qF "$marker" "$path" 2>/dev/null; then
            rm "$path"
            echo "  removed  $path"
        else
            echo "  skipped  $path - not created by this script" >&2
        fi
    elif [[ -d "$path" ]]; then
        if [[ -f "$path/SKILL.md" ]]; then
            rm -rf "$path"
            echo "  removed  $path"
        else
            echo "  skipped  $path - exists but is not a managed skill directory" >&2
        fi
    fi
}

echo "Setup: scope=$scope mode=$mode target=$target_dir"
if [[ "$clean" == "1" ]]; then
    echo "Cleaning managed entries from $target_dir"
else
    mkdir -p "$target_dir"
fi

count=0
for src in "$skills_dir"/*/; do
    [[ -f "$src/SKILL.md" ]] || continue
    name="$(basename "$src")"
    dst="$target_dir/$name"

    if [[ "$clean" == "1" ]]; then
        remove_managed "$dst"
        continue
    fi

    if [[ "$mode" == "link" && -L "$dst" && -f "$dst/SKILL.md" ]]; then
        echo "  linked   $name (already current)"
        count=$((count + 1))
        continue
    fi

    remove_managed "$dst"
    if [[ "$mode" == "link" ]]; then
        src_abs="$(cd "$src" && pwd)"
        ln -s "$src_abs" "$dst"
        echo "  linked   $name -> $src_abs"
    else
        mkdir -p "$dst"
        cp -R "$src". "$dst"/
        echo "  copied   $name"
    fi
    count=$((count + 1))
done

if [[ "$count" == "0" && "$clean" == "0" ]]; then
    echo "error: no skills found in $skills_dir" >&2
    exit 1
fi

if [[ "$clean" == "1" ]]; then
    rmdir "$target_dir" 2>/dev/null || true
    if [[ "$scope" == "local" ]]; then
        rmdir "$repo_root/.agents" 2>/dev/null || true
    fi
    echo "Done: cleaned managed entries from $target_dir"
else
    echo "Done: $count skills installed to $target_dir ($mode)."
    echo "Restart any running agent session to pick them up."
fi

# --- Always-on rules (always installed) --------------------------------------
#
# Skills discovery is not intent mapping: OpenCode and VS Code Copilot both
# discover ~/.agents/skills on their own, but neither forces the discipline of
# loading a matching skill before work starts. Each harness has exactly one
# always-on user-level file that can supply that nudge:
#
#   OpenCode  ~/.config/opencode/AGENTS.md          (combined into every session)
#   Copilot   ~/.copilot/copilot-instructions.md    (Agent Host personal, every repository;
#                                                    VS Code Local agent uses profile storage instead)
#
# Both files are installed by default. Both carry the managed marker: an
# existing file without it is never overwritten, and --clean removes only
# marked ones. Plain Markdown, no frontmatter required for these always-on
# files (frontmatter is only for *.instructions.md).

# Short and harness-neutral. Deliberately tiny: the skill descriptions are
# already in context through skills discovery, so this file must not repeat
# them - it only has to establish the priority.
rules_body="$(cat <<'EOF'
<!-- agent-hub:managed -->

# Skills library

A skills library is installed on this machine at `~/.agents/skills`: a set of
step-by-step procedures for recurring engineering work (planning, debugging,
reviewing, finishing a branch).

Before you start a task, check it. If a skill covers the work you are about to
do, read `~/.agents/skills/<skill>/SKILL.md` and follow it - do not improvise a
procedure when one already exists. Skills are discovered automatically by your
harness, so this file only has to set that priority, nothing more.

Generated by the agent-hub setup script. Re-run it to refresh, or run the
setup script with `--clean` to remove this file.
EOF
)"

install_rules_file() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    if [[ -f "$path" ]] && ! grep -qF "$marker" "$path"; then
        echo "  skipped  $path - exists and was not created by this script (back it up and remove it first to replace it)" >&2
        return 0
    fi
    printf '%s\n' "$rules_body" > "$path"
    echo "  installed $path"
}

install_opencode_rules=1
install_copilot_rules=1
if [[ $skip_opencode_rules == "1" ]]; then install_opencode_rules=0; fi
if [[ $skip_copilot_rules == "1" ]]; then install_copilot_rules=0; fi

if [[ $install_opencode_rules == "1" || $install_copilot_rules == "1" ]]; then
    if [[ $clean == "1" ]]; then
        echo "Cleaning always-on rules files"
    else
        echo "Installing always-on rules files"
    fi
    if [[ $install_opencode_rules == "1" ]]; then
        if [[ $clean == "1" ]]; then remove_managed "$HOME/.config/opencode/AGENTS.md"
        else install_rules_file "$HOME/.config/opencode/AGENTS.md"; fi
    fi
    if [[ $install_copilot_rules == "1" ]]; then
        if [[ $clean == "1" ]]; then remove_managed "$HOME/.copilot/copilot-instructions.md"
        else install_rules_file "$HOME/.copilot/copilot-instructions.md"; fi
    fi
fi
