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
#   Skills discovery is not intent mapping: OpenCode and VS Code Copilot both
#   find ~/.agents/skills on their own, but neither forces the discipline of
#   loading a matching skill before work starts. Two opt-in flags install the
#   single always-on file each harness supports:
#     --opencode-rules  ~/.config/opencode/AGENTS.md          every session
#     --copilot-rules   ~/.copilot/copilot-instructions.md    every repository
#   Install only the one for the harness you use. Existing files are never
#   overwritten unless they carry the managed marker; --clean removes only
#   marked ones.
#
# Idempotent. No dependencies beyond bash/coreutils. No sudo required.
#
# Usage:
#   ./setup.sh
#   ./setup.sh --mode link
#   ./setup.sh --scope local --mode link
#   ./setup.sh --clean
#   ./setup.sh --copilot-rules

set -euo pipefail

scope="global"
mode="copy"
clean=0
opencode_rules=0
copilot_rules=0

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -ge 2 ]] || { echo "error: --scope needs a value" >&2; exit 2; }
            scope="$2"; shift 2 ;;
        --mode)
            [[ $# -ge 2 ]] || { echo "error: --mode needs a value" >&2; exit 2; }
            mode="$2"; shift 2 ;;
        --clean) clean=1; shift ;;
        --opencode-rules) opencode_rules=1; shift ;;
        --copilot-rules) copilot_rules=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

case "$scope" in global|local) ;; *) echo "error: --scope must be global or local" >&2; exit 2 ;; esac
case "$mode" in copy|link) ;; *) echo "error: --mode must be copy or link" >&2; exit 2 ;; esac

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

# --- Always-on rules (opt-in, --opencode-rules / --copilot-rules) -------------
#
# Skills discovery is not intent mapping: OpenCode and VS Code Copilot both
# discover ~/.agents/skills on their own, but neither forces the discipline of
# loading a matching skill before work starts. Each harness has exactly one
# always-on user-level file that can supply that nudge:
#
#   OpenCode  ~/.config/opencode/AGENTS.md          (combined into every session)
#   Copilot   ~/.copilot/copilot-instructions.md    (personal, every repository)
#
# Install only the one for the harness you use. Both files carry the managed
# marker: an existing file without it is never overwritten, and --clean removes
# only marked ones.

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

if [[ $opencode_rules == "1" || $copilot_rules == "1" ]]; then
    if [[ $clean == "1" ]]; then
        echo "Cleaning always-on rules files"
    else
        echo "Installing always-on rules files"
    fi
    if [[ $opencode_rules == "1" ]]; then
        if [[ $clean == "1" ]]; then remove_managed "$HOME/.config/opencode/AGENTS.md"
        else install_rules_file "$HOME/.config/opencode/AGENTS.md"; fi
    fi
    if [[ $copilot_rules == "1" ]]; then
        if [[ $clean == "1" ]]; then remove_managed "$HOME/.copilot/copilot-instructions.md"
        else install_rules_file "$HOME/.copilot/copilot-instructions.md"; fi
    fi
elif [[ $clean == "1" ]]; then
    echo "Note: pass --opencode-rules or --copilot-rules alongside --clean to also remove an installed rules file."
fi
